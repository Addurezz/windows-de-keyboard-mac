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

choose_option() {
    local PS3='Nummer eingeben: '
    local option
    select option in "$@"; do
        if [[ -n $option && $REPLY =~ ^[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
            printf '%s\n' "$((10#${BASH_REMATCH[1]} - 1))"
            return
        fi
        printf 'Bitte eine Nummer aus der Liste eingeben.\n' >&2
    done
    return 1
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

if [[ -x "$source_dir/keyboard-switch" ]]; then
    program="$source_dir/keyboard-switch"
else
    swiftc -O -module-cache-path "$scratch/cache" "$source_dir/KeyboardSwitch.swift" -o "$program"
fi

layouts=$("$program" layouts)

if [[ $# == 1 ]]; then
    printf 'Erkannte Tastaturen (Geräte-ID, Transport, Name):\n'
    "$program" devices
    printf '\nVerfügbare Layouts (ID, Name):\n'
    printf '%s\n' "$layouts"
    exit 0
fi

if [[ $# == 0 ]]; then
    devices=$("$program" devices)
    device_ids=(--any-external)
    device_names=('Alle externen Tastaturen')
    while IFS=$'\t' read -r id transport name; do
        if [[ $id == *:* ]]; then
            device_ids+=("$id")
            device_names+=("$name ($transport)")
        fi
    done <<< "$devices"

    printf 'Welche Tastatur soll den Layoutwechsel auslösen?\n' >&2
    selected=$(choose_option "${device_names[@]}")
    device=${device_ids[$selected]}

    mac_layout=$(plutil -extract ProgramArguments.3 raw -o - "$plist" 2>/dev/null || "$program" current)
    pc_layout=$(plutil -extract ProgramArguments.4 raw -o - "$plist" 2>/dev/null || printf '%s' "$default_external")

    layout_ids=()
    layout_names=()
    mac_name=$mac_layout
    pc_name=$pc_layout
    while IFS=$'\t' read -r id name; do
        [[ -n $id ]] || continue
        layout_ids+=("$id")
        layout_names+=("$name")
        if [[ $id == "$mac_layout" ]]; then mac_name=$name; fi
        if [[ $id == "$pc_layout" ]]; then pc_name=$name; fi
    done <<< "$layouts"

    printf '\nMit externer Tastatur: %s\nNach dem Abziehen: %s\n' "$pc_name" "$mac_name"
    printf 'Enter zum Installieren, A für andere Layouts: '
    IFS= read -r answer
    while [[ -n $answer && $answer != [Aa] ]]; do
        printf 'Drücke Enter oder gib A ein: '
        IFS= read -r answer
    done
    if [[ -n $answer ]]; then
        printf 'Layout mit externer Tastatur\n' >&2
        selected=$(choose_option "${layout_names[@]}")
        pc_layout=${layout_ids[$selected]}
        printf 'Layout nach dem Abziehen\n' >&2
        selected=$(choose_option "${layout_names[@]}")
        mac_layout=${layout_ids[$selected]}
    fi
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
