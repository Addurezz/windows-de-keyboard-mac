# Mac Keyboard Tools

Switch macOS keyboard layouts when you connect or disconnect an external keyboard. Choose the layout that matches the keys printed on the external keyboard and the layout you want back when you unplug it. Both choices can use any available macOS keyboard layout, including custom layouts you have installed.

## Install

1. Download **Mac-Keyboard-Tools.zip** from **Assets** on the [latest GitHub release](https://github.com/Addurezz/mac-keyboard-tools/releases/latest).
2. Unzip it and double-click **Install.command**.
3. Choose a keyboard by number, or choose **All external keyboards**.
4. Choose the external keyboard's layout. The installer suggests your current Mac layout for when the keyboard is disconnected. Press **Enter** to install or **C** to change the choices.

The ZIP includes a ready-to-run binary for Apple silicon and Intel Macs running macOS 13 or later. No Git clone or Xcode installation is required. The switcher starts immediately and runs automatically each time you sign in. Upgrades reuse the layouts you previously configured.

The release is not notarized by Apple. If macOS blocks the first launch and you trust the download, use **System Settings → Privacy & Security → Open Anyway**. [Apple's instructions](https://support.apple.com/en-us/102445)

## Install from source

Run `./install.sh` in a cloned copy of the repository. This requires the Xcode Command Line Tools. To list device and layout IDs or configure both layouts directly:

```bash
./install.sh --list
./install.sh --any-external com.apple.keylayout.US com.apple.keylayout.British
```

The first layout ID is used when the keyboard is disconnected. The second is used when it is connected. To watch an individual keyboard, replace `--any-external` with its device ID from the list.

## What switches

The app changes the macOS session's active layout, so the built-in keyboard also uses the external layout while a matching keyboard is connected. In **All external keyboards** mode, the external layout stays active until the last detected USB or Bluetooth keyboard disconnects. A wireless USB receiver may still report a keyboard while the receiver itself is plugged in. Selecting a specific device ID lets you exclude unrelated receivers. Keyboards of the same model can share an ID.

If macOS changes the layout when you switch documents, check the automatic per-document input source setting under **System Settings → Keyboard → Text Input → Edit**. If the physical key positions are wrong, check whether macOS has identified your keyboard as ANSI, ISO, or JIS. [Apple's keyboard type guide](https://support.apple.com/guide/mac-help/specify-a-keyboard-type-mchlp2886/mac)

The error log is at `~/Library/Logs/io.github.windows-de-keyboard-mac.layout-switch.log`.

## Uninstall

Double-click **Uninstall.command** from the unzipped release, or run `./install.sh --uninstall` from the source folder. The uninstaller stops the switcher and restores the layout configured for when the external keyboard is disconnected.
