import Carbon
import Foundation
import IOKit

private enum KeyboardSelection {
    case device(DeviceID)
    case anyExternal

    init(_ value: String) throws {
        if value == "--any-external" {
            self = .anyExternal
        } else {
            self = .device(try DeviceID(value))
        }
    }

    var deviceID: DeviceID? {
        guard case let .device(id) = self else { return nil }
        return id
    }
}

private struct SwitchError: LocalizedError {
    let message: String

    var errorDescription: String? { message }

    init(_ message: String) {
        self.message = message
    }
}

private struct DeviceID {
    let vendor: UInt16
    let product: UInt16

    init(vendor: UInt16, product: UInt16) {
        self.vendor = vendor
        self.product = product
    }

    init(_ value: String) throws {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let vendor = UInt16(parts[0], radix: 16),
              let product = UInt16(parts[1], radix: 16),
              vendor != 0 else {
            throw SwitchError("Enter a device ID such as 1b1c:1bd7 or use --any-external.")
        }
        self.init(vendor: vendor, product: product)
    }

    var label: String { String(format: "%04x:%04x", Int(vendor), Int(product)) }
}

private func hidMatching(_ id: DeviceID?) -> CFMutableDictionary {
    let matching = IOServiceMatching("IOHIDDevice") as NSMutableDictionary
    if let id {
        matching["IOPropertyMatch"] = ["VendorID": Int(id.vendor), "ProductID": Int(id.product)]
    }
    return matching
}

private func forEachKeyboard(_ id: DeviceID? = nil, _ visit: (io_service_t) -> Void) throws {
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, hidMatching(id), &iterator)
    guard result == KERN_SUCCESS else {
        throw SwitchError("Could not enumerate keyboards (IOKit: \(result)).")
    }
    defer { IOObjectRelease(iterator) }

    while case let service = IOIteratorNext(iterator), service != 0 {
        defer { IOObjectRelease(service) }
        if isKeyboard(service) {
            visit(service)
        }
    }
}

private func registryProperty<T>(_ service: io_service_t, _ key: String) -> T? {
    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? T
}

private func isKeyboard(_ service: io_service_t) -> Bool {
    let usagePage: Int? = registryProperty(service, "PrimaryUsagePage")
    let usage: Int? = registryProperty(service, "PrimaryUsage")
    if usagePage == 1 && usage == 6 { return true }

    let pairs: [[String: Int]] = registryProperty(service, "DeviceUsagePairs") ?? []
    return pairs.contains { $0["DeviceUsagePage"] == 1 && $0["DeviceUsage"] == 6 }
}

private func isExternal(_ service: io_service_t) -> Bool {
    let builtIn: Bool = registryProperty(service, "Built-In") ?? false
    let transport: String = registryProperty(service, "Transport") ?? ""
    return !builtIn && ["USB", "Bluetooth", "BluetoothLowEnergy"].contains(transport)
}

private func inputString(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let value = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
}

private func listLayouts() -> [TISInputSource] {
    let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String]
    return TISCreateInputSourceList(filter as CFDictionary, true)?
        .takeRetainedValue() as? [TISInputSource] ?? []
}

private func currentLayoutID() -> String? {
    guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
    return inputString(current, kTISPropertyInputSourceID)
}

private func layout(_ id: String) throws -> TISInputSource {
    guard let source = listLayouts().first(where: { inputString($0, kTISPropertyInputSourceID) == id }) else {
        throw SwitchError("Layout \(id) is unavailable. Use layouts to see your options.")
    }
    return source
}

private func selectLayout(_ id: String) throws {
    guard currentLayoutID() != id else { return }
    let source = try layout(id)
    if let enabled = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled),
       !CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(enabled).takeUnretainedValue()) {
        let result = TISEnableInputSource(source)
        guard result == noErr else {
            throw SwitchError("Layout \(id) could not be enabled (macOS: \(result)).")
        }
    }

    let result = TISSelectInputSource(source)
    guard result == noErr else {
        throw SwitchError("Layout \(id) could not be selected (macOS: \(result)).")
    }
}

private final class KeyboardWatcher {
    private let selection: KeyboardSelection
    private let macLayout: String
    private let externalLayout: String
    private var pendingUpdate: DispatchWorkItem?
    private var lastConnected: Bool?

    init(selection: KeyboardSelection, macLayout: String, externalLayout: String) {
        self.selection = selection
        self.macLayout = macLayout
        self.externalLayout = externalLayout
    }

    func scheduleUpdate() {
        pendingUpdate?.cancel()
        let update = DispatchWorkItem { [weak self] in
            do {
                try self?.update()
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        pendingUpdate = update
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(350), execute: update)
    }

    private func update() throws {
        var connected = false
        try forEachKeyboard(selection.deviceID) { service in
            switch selection {
            case .device:
                connected = true
            case .anyExternal:
                connected = connected || isExternal(service)
            }
        }
        guard connected != lastConnected else { return }
        try selectLayout(connected ? externalLayout : macLayout)
        lastConnected = connected
    }

    func run() throws {
        _ = try layout(macLayout)
        _ = try layout(externalLayout)

        guard let port = IONotificationPortCreate(kIOMainPortDefault),
              let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() else {
            throw SwitchError("Could not register for IOKit notifications.")
        }
        defer { IONotificationPortDestroy(port) }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        defer { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }

        var iterators: [io_iterator_t] = []
        defer { iterators.forEach { IOObjectRelease($0) } }
        for notification in [kIOMatchedNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, notification, hidMatching(selection.deviceID), { context, iterator in
                    drain(iterator)
                    guard let context else { return }
                    Unmanaged<KeyboardWatcher>.fromOpaque(context).takeUnretainedValue().scheduleUpdate()
                },
                Unmanaged.passUnretained(self).toOpaque(), &iterator
            )
            guard result == KERN_SUCCESS else {
                throw SwitchError("IOKit notification \(notification) failed (\(result)).")
            }
            iterators.append(iterator)
            // Drain the iterator to receive future notifications.
            drain(iterator)
        }

        try update()
        withExtendedLifetime(self) { CFRunLoopRun() }
    }
}

private func drain(_ iterator: io_iterator_t) {
    while case let service = IOIteratorNext(iterator), service != 0 {
        IOObjectRelease(service)
    }
}

private let usage = """
Usage:
  keyboard-switch devices
  keyboard-switch layouts
  keyboard-switch current
  keyboard-switch select <Layout-ID>
  keyboard-switch watch <VID:PID|--any-external> <Mac-layout-ID> <external-layout-ID>
"""

private func run(_ args: [String]) throws {
    switch args.first {
    case "devices" where args.count == 1:
        var devices: Set<String> = []
        try forEachKeyboard { service in
            let name: String = registryProperty(service, "Product") ?? "Unknown device"
            let transport: String = registryProperty(service, "Transport") ?? "?"
            if let vendor: UInt16 = registryProperty(service, "VendorID"), vendor != 0,
               let product: UInt16 = registryProperty(service, "ProductID") {
                devices.insert("\(DeviceID(vendor: vendor, product: product).label)\t\(transport)\t\(name)")
            } else if isExternal(service) {
                devices.insert("no ID\t\(transport)\t\(name)")
            }
        }
        devices.sorted().forEach { print($0) }
    case "layouts" where args.count == 1:
        for source in listLayouts().sorted(by: {
            let left = inputString($0, kTISPropertyLocalizedName) ?? ""
            let right = inputString($1, kTISPropertyLocalizedName) ?? ""
            return left.localizedStandardCompare(right) == .orderedAscending
        }) {
            guard let id = inputString(source, kTISPropertyInputSourceID) else { continue }
            let name = inputString(source, kTISPropertyLocalizedName) ?? id
            print("\(id)\t\(name)")
        }
    case "current" where args.count == 1:
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let id = inputString(source, kTISPropertyInputSourceID) else {
            throw SwitchError("Could not read the current keyboard layout.")
        }
        print(id)
    case "select" where args.count == 2:
        try selectLayout(args[1])
    case "watch" where args.count == 4:
        let selection = try KeyboardSelection(args[1])
        let externalLayout = args[3]
        try KeyboardWatcher(selection: selection, macLayout: args[2], externalLayout: externalLayout).run()
    case "--help", "-h", nil:
        print(usage)
    default:
        throw SwitchError(usage)
    }
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
