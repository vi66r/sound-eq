#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple team ID}"
mkdir -p .build/direct
export DEVELOPMENT_TEAM
python3 - <<'PY'
import os, plistlib
with open('.build/direct/ExportOptions.plist', 'wb') as output:
    plistlib.dump({'method': 'developer-id', 'destination': 'upload',
                  'teamID': os.environ['DEVELOPMENT_TEAM'],
                  'signingStyle': 'automatic'}, output)
PY
xcodebuild -exportArchive -archivePath dist/SoundEQ.xcarchive \
  -exportOptionsPlist .build/direct/ExportOptions.plist -allowProvisioningUpdates
# If Apple is still processing, rerun only this export command after it completes.
xcodebuild -exportNotarizedApp -archivePath dist/SoundEQ.xcarchive -exportPath dist/direct
app='dist/direct/Sound EQ.app'
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app"
spctl --assess --type execute "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/Sound-EQ-$version-mac.zip"
