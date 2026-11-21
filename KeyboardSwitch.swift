import Carbon
import Foundation
import IOKit

private let germanStandard = "com.apple.keylayout.German-DIN-2137"

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
            throw SwitchError("Erwartet wird eine Geräte-ID wie 1b1c:1bd7.")
        }
        self.init(vendor: vendor, product: product)
    }

    var label: String { String(format: "%04x:%04x", Int(vendor), Int(product)) }
}

private func keyboardMatching(_ id: DeviceID? = nil) -> CFMutableDictionary {
    let matching = IOServiceMatching("IOHIDDevice") as NSMutableDictionary
    var properties = ["PrimaryUsagePage": 1, "PrimaryUsage": 6]
    if let id {
        properties["VendorID"] = Int(id.vendor)
        properties["ProductID"] = Int(id.product)
    }
    matching["IOPropertyMatch"] = properties
    return matching
}

private func forEachKeyboard(_ id: DeviceID? = nil, _ visit: (io_service_t) -> Void) throws {
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, keyboardMatching(id), &iterator)
    guard result == KERN_SUCCESS else {
        throw SwitchError("Tastatursuche fehlgeschlagen (IOKit: \(result)).")
    }
    defer { IOObjectRelease(iterator) }

    while case let service = IOIteratorNext(iterator), service != 0 {
        visit(service)
        IOObjectRelease(service)
    }
}

private func registryProperty<T>(_ service: io_service_t, _ key: String) -> T? {
    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? T
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
        throw SwitchError("Layout \(id) fehlt. Verfügbare Layouts zeigt der Befehl layouts.")
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
            throw SwitchError("Layout \(id) konnte nicht aktiviert werden (macOS: \(result)).")
        }
    }

    let result = TISSelectInputSource(source)
    guard result == noErr else {
        throw SwitchError("Layout \(id) konnte nicht ausgewählt werden (macOS: \(result)).")
    }
}

private final class KeyboardWatcher {
    private let id: DeviceID
    private let macLayout: String
    private let pcLayout: String
    private var pendingUpdate: DispatchWorkItem?

    init(id: DeviceID, macLayout: String, pcLayout: String) {
        self.id = id
        self.macLayout = macLayout
        self.pcLayout = pcLayout
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
        try forEachKeyboard(id) { _ in connected = true }
        try selectLayout(connected ? pcLayout : macLayout)
    }

    func run() throws {
        _ = try layout(macLayout)
        _ = try layout(pcLayout)

        guard let port = IONotificationPortCreate(kIOMainPortDefault),
              let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() else {
            throw SwitchError("IOKit-Benachrichtigungen konnten nicht eingerichtet werden.")
        }
        defer { IONotificationPortDestroy(port) }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        defer { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }

        var iterators: [io_iterator_t] = []
        defer { iterators.forEach { IOObjectRelease($0) } }
        for notification in [kIOMatchedNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, notification, keyboardMatching(id), { context, iterator in
                    drain(iterator)
                    guard let context else { return }
                    Unmanaged<KeyboardWatcher>.fromOpaque(context).takeUnretainedValue().scheduleUpdate()
                },
                Unmanaged.passUnretained(self).toOpaque(), &iterator
            )
            guard result == KERN_SUCCESS else {
                throw SwitchError("IOKit-Benachrichtigung \(notification) fehlgeschlagen (\(result)).")
            }
            iterators.append(iterator)
            // Das Leeren des Iterators schaltet künftige Benachrichtigungen frei.
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
Verwendung:
  keyboard-switch devices
  keyboard-switch layouts
  keyboard-switch current
  keyboard-switch select <Layout-ID>
  keyboard-switch watch <VID:PID> <Mac-Layout-ID> [<PC-Layout-ID>]
"""

private func run(_ args: [String]) throws {
    switch args.first {
    case "devices" where args.count == 1:
        var devices: Set<String> = []
        try forEachKeyboard { service in
            guard let vendor: UInt16 = registryProperty(service, "VendorID"), vendor != 0,
                  let product: UInt16 = registryProperty(service, "ProductID") else { return }
            let name: String = registryProperty(service, "Product") ?? "Unbekannt"
            let transport: String = registryProperty(service, "Transport") ?? "?"
            devices.insert("\(DeviceID(vendor: vendor, product: product).label)\t\(transport)\t\(name)")
        }
        devices.sorted().forEach { print($0) }
    case "layouts" where args.count == 1:
        for source in listLayouts() {
            guard let id = inputString(source, kTISPropertyInputSourceID) else { continue }
            let name = inputString(source, kTISPropertyLocalizedName) ?? id
            print("\(id)\t\(name)")
        }
    case "current" where args.count == 1:
        guard let id = currentLayoutID() else {
            throw SwitchError("Aktive Eingabequelle konnte nicht gelesen werden.")
        }
        print(id)
    case "select" where args.count == 2:
        try selectLayout(args[1])
    case "watch" where args.count == 3 || args.count == 4:
        let id = try DeviceID(args[1])
        let pcLayout = args.count == 4 ? args[3] : germanStandard
        try KeyboardWatcher(id: id, macLayout: args[2], pcLayout: pcLayout).run()
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
