#!/bin/bash
set -euo pipefail

label=io.github.windows-de-keyboard-mac.layout-switch
domain="gui/$(id -u)"
service="$domain/$label"
agent_dir="$HOME/Library/LaunchAgents"
plist="$agent_dir/$label.plist"
app_dir="$HOME/Library/Application Support/Windows DE Keyboard Mac"
binary="$app_dir/keyboard-switch"
log="$HOME/Library/Logs/$label.log"
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

stop_agent() {
    if launchctl print "$service" >/dev/null 2>&1; then
        launchctl bootout "$service"
    fi
}

if [[ ${1:-} == --uninstall && $# == 1 ]]; then
    if [[ -f "$plist" ]]; then
        mac_layout=$(plutil -extract ProgramArguments.3 raw -o - "$plist")
        stop_agent
        "$binary" select "$mac_layout"
        rm -f -- "$plist" "$binary"
    fi
    exit 0
fi

if [[ $# -lt 2 || $# -gt 3 || ! $1 =~ ^[[:xdigit:]]{1,4}:[[:xdigit:]]{1,4}$ ]]; then
    echo "Verwendung: ./install.sh <VID:PID> <Mac-Layout-ID> [<PC-Layout-ID>]" >&2
    echo "Deinstallation: ./install.sh --uninstall" >&2
    exit 2
fi

device=$1
if (( 16#${device%:*} == 0 )); then
    echo "Die Hersteller-ID muss ungleich null sein." >&2
    exit 2
fi

mac_layout=$2
pc_layout=${3:-com.apple.keylayout.German-DIN-2137}

scratch=$(mktemp -d "${TMPDIR:-/tmp}/windows-de-keyboard-mac.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

swiftc -O -module-cache-path "$scratch/cache" "$source_dir/KeyboardSwitch.swift" -o "$scratch/keyboard-switch"
layouts=$("$scratch/keyboard-switch" layouts)
for id in "$mac_layout" "$pc_layout"; do
    if ! cut -f 1 <<< "$layouts" | grep -Fx -- "$id" >/dev/null; then
        echo "Layout $id fehlt. Verfügbare Layouts:" >&2
        printf '%s\n' "$layouts" >&2
        exit 1
    fi
done

new_plist="$scratch/agent.plist"
plutil -create xml1 "$new_plist"
plutil -insert Label -string "$label" "$new_plist"
plutil -insert ProgramArguments -json '[]' "$new_plist"
plutil -insert ProgramArguments.0 -string "$binary" "$new_plist"
plutil -insert ProgramArguments.1 -string watch "$new_plist"
plutil -insert ProgramArguments.2 -string "$device" "$new_plist"
plutil -insert ProgramArguments.3 -string "$mac_layout" "$new_plist"
plutil -insert ProgramArguments.4 -string "$pc_layout" "$new_plist"
plutil -insert KeepAlive -bool YES "$new_plist"
plutil -insert StandardErrorPath -string "$log" "$new_plist"
plutil -lint "$new_plist" >/dev/null

mkdir -p -- "$app_dir" "$agent_dir" "$(dirname -- "$log")"
stop_agent
install -m 755 "$scratch/keyboard-switch" "$binary"
install -m 644 "$new_plist" "$plist"
launchctl bootstrap "$domain" "$plist"
printf 'Layout-Umschalter gestartet. Fehlerprotokoll: %s\n' "$log"
