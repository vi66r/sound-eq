#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your paid Apple Developer team ID}"
archive="$PWD/dist/SoundEQ.xcarchive"
if [ ! -d "$archive" ]; then
    echo "Run scripts/archive-testflight.sh first." >&2
    exit 1
fi
mkdir -p .build/testflight
export_options="$PWD/.build/testflight/ExportOptions.plist"
export DEVELOPMENT_TEAM
python3 - "$export_options" <<'PY'
import os, plistlib, sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({
        'method': 'app-store-connect',
        'destination': 'upload',
        'teamID': os.environ['DEVELOPMENT_TEAM'],
        'signingStyle': 'automatic',
        'uploadSymbols': True,
        'manageAppVersionAndBuildNumber': False,
    }, output)
PY
# Uses the Apple Account signed into Xcode; no passwords or API keys in this script.
xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist "$export_options" -exportPath dist/testflight \
    -allowProvisioningUpdates
