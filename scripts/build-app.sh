#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if pgrep -x SoundEQ >/dev/null; then
    echo "Quit Sound EQ (Command-Q) before rebuilding so its running executable stays intact." >&2
    exit 1
fi
configuration="${CONFIGURATION:-release}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="$PWD/dist/Sound EQ.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/SoundEQ" "$app/Contents/MacOS/SoundEQ"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift .build/SoundEQ.iconset
iconutil -c icns .build/SoundEQ.iconset -o "$app/Contents/Resources/SoundEQ-Aero.icns"
# Override with a stable Developer ID for distribution or stable TCC identity across rebuilds.
codesign --force --sign "${SIGNING_IDENTITY:--}" --identifier network.rafi.sound-eq "$app"
codesign --verify --strict "$app"
echo "Built $app"
