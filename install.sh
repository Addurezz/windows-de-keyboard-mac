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
default_external=com.apple.keylayout.German-DIN-2137

usage() {
    cat <<'USAGE'
Einrichtung:   ./install.sh
Geräte und Layouts anzeigen: ./install.sh --list
Direkt:        ./install.sh <VID:PID|--any-external> <Mac-Layout-ID> [<Extern-Layout-ID>]
Deinstallation: ./install.sh --uninstall
USAGE
}

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

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    usage
    exit 0
fi

if [[ $# == 1 && $1 != --list ]] || [[ $# -gt 3 ]]; then
    usage >&2
    exit 2
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/windows-de-keyboard-mac.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
program="$scratch/keyboard-switch"

swiftc -O -module-cache-path "$scratch/cache" "$source_dir/KeyboardSwitch.swift" -o "$program"

if [[ $# == 1 ]]; then
    printf 'Erkannte Tastaturen (Geräte-ID, Transport, Name):\n'
    "$program" devices
    printf '\nVerfügbare Layouts (ID, Name):\n'
    "$program" layouts
    exit 0
fi

if [[ $# == 0 ]]; then
    printf 'Erkannte Tastaturen (Geräte-ID, Transport, Name):\n'
    "$program" devices
    printf 'Geräte-ID eingeben oder --any-external für alle externen Tastaturen: '
    IFS= read -r device

    default_mac=$(plutil -extract ProgramArguments.3 raw -o - "$plist" 2>/dev/null || "$program" current)
    printf 'Mac-Layout-ID [%s]: ' "$default_mac"
    IFS= read -r mac_layout
    mac_layout=${mac_layout:-$default_mac}
    printf 'Externes Layout [%s]: ' "$default_external"
    IFS= read -r pc_layout
    pc_layout=${pc_layout:-$default_external}
else
    device=$1
    mac_layout=$2
    pc_layout=${3:-$default_external}
fi

if [[ $device != --any-external ]]; then
    if [[ ! $device =~ ^[[:xdigit:]]{1,4}:[[:xdigit:]]{1,4}$ ]] || (( 16#${device%:*} == 0 )); then
        printf 'Ungültige Geräte-ID. Gib VID:PID oder --any-external an.\n' >&2
        exit 2
    fi
fi

layouts=$("$program" layouts)
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
install -m 755 "$program" "$binary"
install -m 644 "$new_plist" "$plist"
launchctl bootstrap "$domain" "$plist"
printf 'Layout-Umschalter gestartet. Fehlerprotokoll: %s\n' "$log"
