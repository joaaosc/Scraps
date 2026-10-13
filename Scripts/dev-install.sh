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

if [ "$(uname -s)" != Darwin ]; then
    echo "Run this installer on a Mac with Xcode 27." >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="build.noindex/DerivedData"
CONFIGURATION="${CONFIGURATION:-Debug}"
PRODUCT="$ROOT/$DERIVED/Build/Products/$CONFIGURATION/Scraps.app"
DESTINATION="/Applications/Scraps.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
STAGING_ROOT=""
PREVIOUS_PRODUCT=""
INSTALLED_NEW=""

cleanup() {
    local status=$?
    trap - EXIT
    if [ "$status" -ne 0 ] && [ -n "$PREVIOUS_PRODUCT" ] && [ -e "$PREVIOUS_PRODUCT" ]; then
        if [ -n "$INSTALLED_NEW" ] && [ -e "$DESTINATION" ]; then
            mv "$DESTINATION" "$STAGING_ROOT/FailedScraps.app" || return "$status"
        fi
        if [ ! -e "$DESTINATION" ]; then
            mv "$PREVIOUS_PRODUCT" "$DESTINATION"
            "$LSREGISTER" -f "$DESTINATION" || true
            echo "The previous app has been restored at $DESTINATION." >&2
        fi
    fi
    if [ -n "$STAGING_ROOT" ] && [ -d "$STAGING_ROOT" ]; then
        rm -rf "$STAGING_ROOT"
    fi
    exit "$status"
}
trap cleanup EXIT

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
    -allowProvisioningUpdates build

# Validate the complete copy before touching the installed app.
echo "==> Preparing and verifying the new app"
STAGING_ROOT="$(mktemp -d /Applications/.Scraps-install.XXXXXX)"
ditto "$PRODUCT" "$STAGING_ROOT/Scraps.app"
codesign --verify --deep --strict "$STAGING_ROOT/Scraps.app"
python3 Scripts/verify-product.py "$STAGING_ROOT/Scraps.app"

# The running copy holds the bundle open; replacing it underneath leaves the
# process talking to a deleted bundle. Asked to quit rather than killed, so the
# stickies write what they have not saved yet.
if pgrep -xq Scraps; then
    echo "==> Asking Scraps to save and quit"
    if ! osascript -e 'tell application id "com.joaocosta.Scraps" to quit'; then
        echo "Scraps did not quit. The installed app has been preserved." >&2
        exit 1
    fi
    for ((attempt = 0; attempt < 30; attempt++)); do
        if ! pgrep -xq Scraps; then break; fi
        sleep 1
    done
    if pgrep -xq Scraps; then
        echo "Scraps is still running. Finish saving and quit it before installing again." >&2
        exit 1
    fi
fi

echo "==> Installing into $DESTINATION"
# Into the Trash rather than deleted, so a bad install can be undone.
if [ -e "$DESTINATION" ]; then
    mkdir -p "$HOME/.Trash"
    PREVIOUS_PRODUCT="$HOME/.Trash/Scraps $(date +%Y-%m-%d\ %H.%M.%S) $$.app"
    if [ -e "$PREVIOUS_PRODUCT" ]; then
        echo "The backup path is occupied: $PREVIOUS_PRODUCT" >&2
        exit 1
    fi
    mv "$DESTINATION" "$PREVIOUS_PRODUCT"
fi
mv "$STAGING_ROOT/Scraps.app" "$DESTINATION"
INSTALLED_NEW="yes"

echo "==> Verifying the signature"
codesign --verify --deep --strict "$DESTINATION"

echo "==> Registering the installed copy, and only it"
"$LSREGISTER" -f "$DESTINATION"
"$LSREGISTER" -u "$PRODUCT" || true

if [ -z "$SKIP_LAUNCH" ]; then
    echo "==> Opening"
    open -a "$DESTINATION"
fi

echo "Installed $(defaults read "$DESTINATION/Contents/Info.plist" CFBundleShortVersionString) ($(defaults read "$DESTINATION/Contents/Info.plist" CFBundleVersion)) at $DESTINATION"
