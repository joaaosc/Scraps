#!/bin/bash
# Produces an App Store archive; does not upload or publish it.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
PLATFORM="${1:-macOS}"
case "$PLATFORM" in
    macOS)
        SCHEME=Scraps
        DESTINATION='generic/platform=macOS'
        SIGNING_IDENTITY='Apple Distribution'
        ;;
    iOS)
        SCHEME=ScrapsMobile
        DESTINATION='generic/platform=iOS'
        SIGNING_IDENTITY='Apple Distribution'
        ;;
    *) echo "Usage: Scripts/archive.sh [macOS|iOS]" >&2; exit 2 ;;
esac
xcodegen generate
xcodebuild -project Scraps.xcodeproj -scheme "$SCHEME" -configuration Release \
    -destination "$DESTINATION" -derivedDataPath build.noindex/DerivedData \
    -archivePath "build.noindex/Archives/$SCHEME.xcarchive" \
    archive CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
PRODUCT="build.noindex/Archives/$SCHEME.xcarchive/Products/Applications/Scraps.app"
codesign --verify --deep --strict "$PRODUCT"
codesign -d --entitlements - --xml "$PRODUCT"
python3 Scripts/verify-product.py "$PRODUCT" --distribution
echo "Archive ready in build.noindex/Archives/$SCHEME.xcarchive"
