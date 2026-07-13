#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/AirGuard.xcodeproj"
SCHEME="AirGuard"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
OUTPUT_DIR="$ROOT_DIR/build/Release"
APP_NAME="AirSentry.app"
APP_PATH="$OUTPUT_DIR/$APP_NAME"
INSTALL_PATH="${INSTALL_PATH:-/Applications/$APP_NAME}"
HOST_APP_ENTITLEMENTS="$ROOT_DIR/AirGuard/DirectDistribution.entitlements"
FINDER_EXTENSION_ENTITLEMENTS="$ROOT_DIR/AirGuardFinderExtension/FinderExtension.entitlements"
TEAM_ID="${TEAM_ID:-}"
BUNDLE_ID="${BUNDLE_ID:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
UNSIGNED=false

usage() {
    cat <<'EOF'
Usage: scripts/build-release.sh [options]

Options:
  --team-id ID                   Apple Developer Team ID.
  --bundle-id ID                 Override the host app bundle identifier.
  --identity "CERTIFICATE NAME"  Sign with a specific certificate.
  --adhoc                        Sign with an ad-hoc identity for local Finder extension testing.
  --unsigned                     Build without a developer signature.
  --clean                        Remove release build intermediates first.
  --install                      Copy the app to /Applications and refresh Finder extension.
  --reload-finder-extension      Refresh the installed Finder extension without rebuilding.
  -h, --help                     Show this help.

The script automatically prefers a "Developer ID Application" identity, then
an "Apple Distribution" identity, then an "Apple Development" identity.
TEAM_ID, BUNDLE_ID, and SIGN_IDENTITY can also specify the same values.
INSTALL_PATH can override the install location used by --install.
EOF
}

clean=false
install=false
reload_finder_extension=false
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
        --identity)
            [[ $# -ge 2 ]] || { echo "Missing value for --identity" >&2; exit 2; }
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --adhoc)
            SIGN_IDENTITY="-"
            shift
            ;;
        --unsigned)
            UNSIGNED=true
            shift
            ;;
        --clean)
            clean=true
            shift
            ;;
        --install)
            install=true
            shift
            ;;
        --reload-finder-extension)
            reload_finder_extension=true
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

finder_extension_path_for_app() {
    local app_path="$1"
    find "$app_path/Contents/PlugIns" -maxdepth 1 -name "*.appex" -type d -print -quit 2>/dev/null || true
}

finder_extension_bundle_id() {
    local extension_path="$1"
    [[ -n "$extension_path" && -f "$extension_path/Contents/Info.plist" ]] || return 0
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$extension_path/Contents/Info.plist" 2>/dev/null || true
}

refresh_app_bundle_timestamp() {
    local app_path="$1"
    [[ -d "$app_path" ]] || return 0
    /usr/bin/touch "$app_path"
}

unregister_finder_extension() {
    local app_path="$1"
    local extension_path
    extension_path="$(finder_extension_path_for_app "$app_path")"
    [[ -n "$extension_path" ]] || return 0
    echo "Unregistering Finder extension: $extension_path"
    /usr/bin/pluginkit -r "$extension_path" 2>/dev/null || true
}

refresh_finder_extension() {
    local app_path="$1"
    local extension_path bundle_id
    extension_path="$(finder_extension_path_for_app "$app_path")"
    if [[ -z "$extension_path" ]]; then
        echo "Warning: Finder extension was not found in $app_path" >&2
        return 0
    fi

    echo "Refreshing LaunchServices registration..."
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$app_path" 2>/dev/null || true

    bundle_id="$(finder_extension_bundle_id "$extension_path")"
    if [[ -n "$bundle_id" ]]; then
        echo "Enabling Finder extension: $bundle_id"
        /usr/bin/pluginkit -e use -i "$bundle_id" 2>/dev/null || true
    fi

    echo "Restarting Finder..."
    /usr/bin/killall Finder 2>/dev/null || true
}

if [[ "$reload_finder_extension" == true && "$install" == false ]]; then
    unregister_finder_extension "$INSTALL_PATH"
    refresh_finder_extension "$INSTALL_PATH"
    exit 0
fi

if [[ -n "$BUNDLE_ID" && "$BUNDLE_ID" == com.example.* ]]; then
    echo "BUNDLE_ID must not use the com.example placeholder." >&2
    exit 2
fi

find_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -nE 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "([^"]+)".*/\1/p' \
        | awk -v team_id="$TEAM_ID" '
            team_id != "" && index($0, "(" team_id ")") == 0 { next }
            /^Developer ID Application:/ && developer_id == "" { developer_id = $0 }
            /^Apple Distribution:/ && distribution == "" { distribution = $0 }
            /^Apple Development:/ && development == "" { development = $0 }
            /^Mac Developer:/ && development == "" { development = $0 }
            END {
                if (developer_id != "") print developer_id
                else if (distribution != "") print distribution
                else if (development != "") print development
            }
        ' \
        | head -n 1
}

if [[ "$UNSIGNED" == false && -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(find_identity || true)"
fi

if [[ "$clean" == true ]]; then
    rm -rf "$DERIVED_DATA" "$OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR"

build_settings=(CODE_SIGNING_ALLOWED=NO)
if [[ -n "$TEAM_ID" ]]; then
    build_settings+=(DEVELOPMENT_TEAM="$TEAM_ID")
fi
if [[ -n "$BUNDLE_ID" ]]; then
    build_settings+=(AIR_SENTRY_BUNDLE_ID="$BUNDLE_ID")
fi

echo "Building Release..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_ENTITLEMENTS=AirGuard/DirectDistribution.entitlements \
    ENABLE_APP_SANDBOX=NO \
    "${build_settings[@]}" \
    build

rm -rf "$APP_PATH"
ditto "$DERIVED_DATA/Build/Products/Release/$APP_NAME" "$APP_PATH"

if [[ "$UNSIGNED" == true ]]; then
    echo "Skipping code signing (--unsigned)."
elif [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Signing with: $SIGN_IDENTITY"
    sign_args=(--force --options runtime --sign "$SIGN_IDENTITY")
    if [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
        sign_args=(--timestamp "${sign_args[@]}")
    fi
    while IFS= read -r -d '' framework_path; do
        codesign --remove-signature "$framework_path" 2>/dev/null || true
        codesign "${sign_args[@]}" "$framework_path"
    done < <(find "$APP_PATH/Contents/Frameworks" -name "*.framework" -type d -print0 2>/dev/null)
    while IFS= read -r -d '' extension_path; do
        codesign --remove-signature "$extension_path" 2>/dev/null || true
        if [[ -f "$FINDER_EXTENSION_ENTITLEMENTS" ]]; then
            codesign "${sign_args[@]}" --entitlements "$FINDER_EXTENSION_ENTITLEMENTS" "$extension_path"
        else
            codesign "${sign_args[@]}" "$extension_path"
        fi
    done < <(find "$APP_PATH/Contents/PlugIns" -name "*.appex" -type d -print0 2>/dev/null)
    codesign --remove-signature "$APP_PATH" 2>/dev/null || true
    if [[ -f "$HOST_APP_ENTITLEMENTS" ]]; then
        codesign "${sign_args[@]}" --entitlements "$HOST_APP_ENTITLEMENTS" "$APP_PATH"
    else
        codesign "${sign_args[@]}" "$APP_PATH"
    fi
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
else
    echo "Warning: no valid code-signing identity was found; output is unsigned." >&2
    echo "Install a certificate or rerun with --identity \"CERTIFICATE NAME\"." >&2
fi

refresh_app_bundle_timestamp "$APP_PATH"

echo
echo "Release app: $APP_PATH"
du -sh "$APP_PATH"

if [[ "$install" == true ]]; then
    echo
    echo "Installing to: $INSTALL_PATH"
    unregister_finder_extension "$INSTALL_PATH"
    rm -rf "$INSTALL_PATH"
    ditto "$APP_PATH" "$INSTALL_PATH"
    refresh_app_bundle_timestamp "$INSTALL_PATH"
    refresh_finder_extension "$INSTALL_PATH"
    echo "Installed app: $INSTALL_PATH"
fi
