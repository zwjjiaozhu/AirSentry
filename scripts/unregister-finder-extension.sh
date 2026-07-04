#!/bin/bash

set -euo pipefail

APP_NAME="AirSentry.app"
INSTALL_PATH="${INSTALL_PATH:-/Applications/$APP_NAME}"
BUNDLE_ID="${BUNDLE_ID:-com.sjzm.airsentry.finderextension}"
RESTART_FINDER=true
DRY_RUN=false

usage() {
    cat <<'EOF'
Usage: scripts/unregister-finder-extension.sh [options]

Options:
  --bundle-id ID       FinderSync extension bundle identifier.
  --app PATH           Host app path. Defaults to /Applications/AirSentry.app.
  --no-restart-finder  Do not restart Finder after unregistering.
  --dry-run            Print actions without changing registration.
  -h, --help           Show this help.

BUNDLE_ID and INSTALL_PATH can also be provided as environment variables.
EOF
}

while (($# > 0)); do
    case "$1" in
        --bundle-id)
            [[ $# -ge 2 ]] || { echo "Missing value for --bundle-id" >&2; exit 2; }
            BUNDLE_ID="$2"
            shift 2
            ;;
        --app)
            [[ $# -ge 2 ]] || { echo "Missing value for --app" >&2; exit 2; }
            INSTALL_PATH="$2"
            shift 2
            ;;
        --no-restart-finder)
            RESTART_FINDER=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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

run() {
    if [[ "$DRY_RUN" == true ]]; then
        printf 'DRY RUN:'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi

    "$@"
}

finder_extension_path_for_app() {
    local app_path="$1"
    find "$app_path/Contents/PlugIns" -maxdepth 1 -name "*.appex" -type d -print -quit 2>/dev/null || true
}

unregister_path() {
    local extension_path="$1"
    [[ -n "$extension_path" ]] || return 0

    echo "Unregistering Finder extension: $extension_path"
    run /usr/bin/pluginkit -r "$extension_path" 2>/dev/null || true
}

echo "Target bundle id: $BUNDLE_ID"

installed_extension_path="$(finder_extension_path_for_app "$INSTALL_PATH")"
if [[ -n "$installed_extension_path" ]]; then
    unregister_path "$installed_extension_path"
fi

while IFS= read -r registered_path; do
    [[ -n "$registered_path" ]] || continue
    if [[ "$registered_path" != "$installed_extension_path" ]]; then
        unregister_path "$registered_path"
    fi
done < <(
    /usr/bin/pluginkit -m -v -p com.apple.FinderSync 2>/dev/null \
        | awk -F '\t' -v bundle_id="$BUNDLE_ID" 'index($1, bundle_id) { print $NF }'
)

if [[ "$RESTART_FINDER" == true ]]; then
    echo "Restarting Finder..."
    run /usr/bin/killall Finder 2>/dev/null || true
fi

echo "Finder extension unregister complete."
