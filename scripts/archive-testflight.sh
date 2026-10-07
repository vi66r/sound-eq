#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your paid Apple Developer team ID}"
days_since_2020=$(( ($(date -u +%s) - 1577836800) / 86400 ))
build_number="${BUILD_NUMBER:-$days_since_2020.$(date -u +%H).$(date -u +%M)}"
xcodebuild archive \
    -project SoundEQ.xcodeproj -scheme SoundEQ -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath .build/xcode -archivePath dist/SoundEQ.xcarchive \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CURRENT_PROJECT_VERSION="$build_number"
echo "Archive created: $PWD/dist/SoundEQ.xcarchive"
echo "Open in Xcode Organizer to validate and upload to App Store Connect."
