#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/AirGuard.xcodeproj"
SCHEME="AirGuard"
ARCHIVE_PATH="$ROOT_DIR/build/AppStore/AirSentry.xcarchive"
EXPORT_DIR="$ROOT_DIR/build/AppStore/Export"
EXPORT_OPTIONS_TEMPLATE="$ROOT_DIR/config/AppStoreExportOptions.plist"
EXPORT_OPTIONS="$ROOT_DIR/build/AppStore/ExportOptions.plist"
ENTITLEMENTS="AirGuard/AppStore.entitlements"
TEAM_ID="${TEAM_ID:-}"
BUNDLE_ID="${BUNDLE_ID:-}"
UPLOAD=false
CLEAN=false

usage() {
    cat <<'EOF'
Usage: scripts/archive-app-store.sh [options]

Required:
  TEAM_ID=XXXXXXXXXX             Apple Developer Team ID.
  BUNDLE_ID=com.example.app      Registered App Store Connect Bundle ID.

Options:
  --team-id ID                   Override TEAM_ID.
  --bundle-id ID                 Override BUNDLE_ID.
  --upload                       Upload the archive to App Store Connect.
  --clean                        Remove previous App Store output first.
  -h, --help                     Show this help.

Without --upload, the script exports a signed App Store Connect package locally.
Xcode must be signed into the Apple Developer account and able to manage signing.
EOF
}

while (($# > 0)); do
    case "$1" in
        --team-id)
            [[ $# -ge 2 ]] || { echo "Missing value for --team-id" >&2; exit 2; }
            TEAM_ID="$2"
            shift 2
            ;;
        --bundle-id)
            [[ $# -ge 2 ]] || { echo "Missing value for --bundle-id" >&2; exit 2; }
            BUNDLE_ID="$2"
            shift 2
            ;;
        --upload)
            UPLOAD=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[[ -n "$TEAM_ID" ]] || { echo "TEAM_ID is required." >&2; exit 2; }
[[ -n "$BUNDLE_ID" ]] || { echo "BUNDLE_ID is required." >&2; exit 2; }
[[ "$BUNDLE_ID" != com.example.* ]] || {
    echo "BUNDLE_ID must not use the com.example placeholder." >&2
    exit 2
}

if ! security find-identity -v -p codesigning | grep -Eq '"(Apple Distribution|3rd Party Mac Developer Application):'; then
    echo "Warning: no local Apple Distribution identity found." >&2
    echo "Xcode may download a cloud-managed certificate during archive/export." >&2
fi

if [[ "$CLEAN" == true ]]; then
    rm -rf "$ROOT_DIR/build/AppStore"
fi

mkdir -p "$ROOT_DIR/build/AppStore"

echo "Archiving App Store build..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
    ENABLE_APP_SANDBOX=YES \
    EXCLUDED_SOURCE_FILE_NAMES="HIDTemperatureReader.m ASMediaRemoteBridge.m MediaRemoteAdapter.framework" \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS=APP_STORE \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) APP_STORE' \
    archive

ditto "$EXPORT_OPTIONS_TEMPLATE" "$EXPORT_OPTIONS"
if [[ "$UPLOAD" == true ]]; then
    /usr/libexec/PlistBuddy -c "Set :destination upload" "$EXPORT_OPTIONS"
    echo "Uploading archive to App Store Connect..."
else
    rm -rf "$EXPORT_DIR"
    echo "Exporting signed App Store Connect package..."
fi

xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates

echo
if [[ "$UPLOAD" == true ]]; then
    echo "Upload completed. Check App Store Connect processing status."
else
    echo "App Store export: $EXPORT_DIR"
fi
