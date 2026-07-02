#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/AirGuard.xcodeproj"
SCHEME="AirGuard"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
OUTPUT_DIR="$ROOT_DIR/build/Release"
APP_NAME="AirSentry.app"
APP_PATH="$OUTPUT_DIR/$APP_NAME"
TEAM_ID="${TEAM_ID:-}"
BUNDLE_ID="${BUNDLE_ID:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
UNSIGNED=false

usage() {
    cat <<'EOF'
Usage: scripts/build-release.sh [options]

Options:
  --team-id ID                   Apple Developer Team ID.
  --bundle-id ID                 Override PRODUCT_BUNDLE_IDENTIFIER.
  --identity "CERTIFICATE NAME"  Sign with a specific certificate.
  --unsigned                     Build without a developer signature.
  --clean                        Remove release build intermediates first.
  -h, --help                     Show this help.

The script automatically prefers a "Developer ID Application" identity, then
an "Apple Distribution" identity, then an "Apple Development" identity.
TEAM_ID, BUNDLE_ID, and SIGN_IDENTITY can also specify the same values.
EOF
}

clean=false
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
        --unsigned)
            UNSIGNED=true
            shift
            ;;
        --clean)
            clean=true
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
    build_settings+=(PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID")
fi

echo "Building Release..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
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
    codesign "${sign_args[@]}" "$APP_PATH"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
else
    echo "Warning: no valid code-signing identity was found; output is unsigned." >&2
    echo "Install a certificate or rerun with --identity \"CERTIFICATE NAME\"." >&2
fi

echo
echo "Release app: $APP_PATH"
du -sh "$APP_PATH"
