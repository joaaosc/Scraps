#!/bin/bash
# Builds Debug and replaces the copy in /Applications.
#
# Spotlight, Siri and Shortcuts read the bundle Launch Services has registered,
# so a change to the intents is not observable until the app is installed. The
# build product carries the same identifier as the installed app, and a second
# registered bundle is what makes Spotlight list the app twice, so the product
# is unregistered once it has been copied.
#
# With --skip-launch it stops before opening the app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="build.noindex/DerivedData"
CONFIGURATION="${CONFIGURATION:-Debug}"
PRODUCT="$ROOT/$DERIVED/Build/Products/$CONFIGURATION/Scraps.app"
DESTINATION="/Applications/Scraps.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

SKIP_LAUNCH=""
for argument in "$@"; do
    case "$argument" in
        --skip-launch) SKIP_LAUNCH="yes" ;;
        *) echo "Unknown argument: $argument" >&2; exit 2 ;;
    esac
done

# Regenerating unconditionally would rewrite the project file under an open
# Xcode on every run, so it happens only when project.yml is actually newer.
if [ "project.yml" -nt "Scraps.xcodeproj/project.pbxproj" ]; then
    echo "==> project.yml changed, regenerating the project"
    xcodegen generate --quiet
fi

echo "==> Building Scraps ($CONFIGURATION)"
xcodebuild -project Scraps.xcodeproj \
    -scheme Scraps \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    build

echo "==> Installing into $DESTINATION"
# The running copy holds the bundle open; replacing it underneath leaves the
# process talking to a deleted bundle. Asked to quit rather than killed, so the
# stickies write what they have not saved yet.
if pgrep -xq Scraps; then
    osascript -e 'tell application id "com.joaocosta.Scraps" to quit' 2>/dev/null || true
fi

# Into the Trash rather than deleted, so a bad install can be undone.
if [ -e "$DESTINATION" ]; then
    mv "$DESTINATION" "$HOME/.Trash/Scraps $(date +%Y-%m-%d\ %H.%M.%S).app"
fi
cp -R "$PRODUCT" "$DESTINATION"

echo "==> Verifying the signature"
codesign --verify --strict "$DESTINATION"

echo "==> Registering the installed copy, and only it"
"$LSREGISTER" -f "$DESTINATION"
"$LSREGISTER" -u "$PRODUCT" || true

if [ -z "$SKIP_LAUNCH" ]; then
    echo "==> Opening"
    open -a "$DESTINATION"
fi

echo "Installed $(defaults read "$DESTINATION/Contents/Info.plist" CFBundleShortVersionString) ($(defaults read "$DESTINATION/Contents/Info.plist" CFBundleVersion)) at $DESTINATION"
