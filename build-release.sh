#!/bin/bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
output="${1:-.build/Tastatur-Umschalter-macOS.zip}"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/keyboard-release.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
folder="$scratch/Tastatur-Umschalter"
mkdir -p -- "$folder" "$(dirname -- "$output")"

for arch in arm64 x86_64; do
    xcrun swiftc -O -target "$arch-apple-macos13.0" -module-cache-path "$scratch/cache" \
        KeyboardSwitch.swift -o "$scratch/keyboard-switch-$arch"
done
xcrun lipo -create "$scratch/keyboard-switch-arm64" "$scratch/keyboard-switch-x86_64" \
    -output "$folder/keyboard-switch"
codesign --force --sign - "$folder/keyboard-switch"
xcrun lipo "$folder/keyboard-switch" -verify_arch arm64 x86_64
codesign --verify --strict --all-architectures "$folder/keyboard-switch"
install -m 755 install.sh "$folder/install.sh"

make_launcher() {
    local filename=$1
    shift
    {
        printf '%s\n' '#!/bin/bash' 'cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1'
        printf '/bin/bash ./install.sh%s\n' "${1:+ $1}"
    } > "$folder/$filename"
    chmod +x "$folder/$filename"
}

make_launcher Installieren.command
make_launcher Deinstallieren.command --uninstall
ditto -c -k --keepParent "$folder" "$scratch/release.zip"
install -m 644 "$scratch/release.zip" "$output"
printf '%s\n' "$output"
