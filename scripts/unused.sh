#!/usr/bin/env bash
# Run Periphery to find unused code
# Usage:
#   ./scripts/unused.sh [--json]
#   ./scripts/unused.sh --skip-apps
#   ./scripts/unused.sh --skip-packages

set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/tooling.sh

PERIPHERY_BIN="$(resolve_tool_or_die periphery)"

JSON_OUTPUT=0
SCAN_APPS=1
SCAN_PACKAGES=1
SKIP_PACKAGE_BUILD=0
REPO_ROOT="$(pwd)"
XCODE_PROJECT="Devys.xcodeproj"
APP_PERIPHERY_CONFIG="$REPO_ROOT/.periphery.yml"
PACKAGE_PERIPHERY_CONFIG="$REPO_ROOT/.periphery-package.yml"
METAL_ASCII_PERIPHERY_CONFIG="$REPO_ROOT/.periphery-package-metalascii.yml"

run_periphery() {
    local config_path="$1"
    shift

    # Run Periphery in a minimal shell environment. The quality gate is launched
    # from Xcode scheme pre-actions, and inherited Xcode build variables can
    # interfere with nested `swift build`/macro plugin resolution.
    env -i \
        PATH="${PATH}" \
        HOME="${HOME}" \
        USER="${USER:-}" \
        LOGNAME="${LOGNAME:-}" \
        SHELL="${SHELL:-/bin/bash}" \
        TMPDIR="${TMPDIR:-/tmp}" \
        LANG="${LANG:-en_US.UTF-8}" \
        DEVYS_SKIP_QUALITY_GATE=1 \
        "$PERIPHERY_BIN" scan --disable-update-check --config "$config_path" "$@"
}

scan_package() {
    local package_path="$1"
    local output_file="$2"
    local package_config="$PACKAGE_PERIPHERY_CONFIG"

    if [[ "$package_path" == "Packages/MetalASCII" && -f "$METAL_ASCII_PERIPHERY_CONFIG" ]]; then
        package_config="$METAL_ASCII_PERIPHERY_CONFIG"
    fi

    local manifest_file
    manifest_file="$(mktemp)"

    env \
        -u SWIFT_DEBUG_INFORMATION_FORMAT \
        -u SWIFT_DEBUG_INFORMATION_VERSION \
        swift package describe --package-path "$package_path" --type json >"$manifest_file"

    scan_args=(--project-root "$package_path" --json-package-manifest-path "$manifest_file")
    if [[ "$SKIP_PACKAGE_BUILD" -eq 1 ]]; then
        scan_args+=(--skip-build)
    fi

    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
        run_periphery "$package_config" "${scan_args[@]}" --format json >"$output_file"
    else
        run_periphery "$package_config" "${scan_args[@]}" >"$output_file"
    fi

    rm -f "$manifest_file"
}

scan_scheme() {
    local scheme="$1"
    local output_file="$2"

    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
        run_periphery "$APP_PERIPHERY_CONFIG" --project Devys.xcodeproj --schemes "$scheme" --format json >"$output_file"
    else
        run_periphery "$APP_PERIPHERY_CONFIG" --project Devys.xcodeproj --schemes "$scheme" >"$output_file"
    fi
}

collect_package_targets() {
    package_targets=( )

    for package_manifest in Packages/*/Package.swift; do
        [[ -f "$package_manifest" ]] || continue
        package_targets+=("${package_manifest%/Package.swift}")
    done

    if [[ -f "Apps/mac-server/Package.swift" ]]; then
        package_targets+=("Apps/mac-server")
    fi
}

collect_app_schemes() {
    app_schemes=( )
    local line
    local in_targets=0
    local trimmed

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*Targets: ]]; then
            in_targets=1
            continue
        fi

        if [[ "$in_targets" -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]*Build[[:space:]]Configurations: ]]; then
                break
            fi

            trimmed="${line#"${line%%[![:space:]]*}"}"
            [[ -z "$trimmed" ]] && continue
            app_schemes+=("$trimmed")
        fi
    done < <(xcodebuild -list -project "$XCODE_PROJECT" 2>/dev/null)

    if [[ ${#app_schemes[@]} -eq 0 ]]; then
        echo "Failed to discover app targets from $XCODE_PROJECT."
        exit 1
    fi
}

for arg in "$@"; do
    case "$arg" in
        --json)
            JSON_OUTPUT=1
            ;;
        --skip-apps)
            SCAN_APPS=0
            ;;
        --skip-packages)
            SCAN_PACKAGES=0
            ;;
        --help|-h)
            cat <<'USAGE'
Usage:
  ./scripts/unused.sh
  ./scripts/unused.sh --json
  ./scripts/unused.sh --skip-apps
  ./scripts/unused.sh --skip-packages
  ./scripts/unused.sh --skip-package-build
USAGE
            exit 0
            ;;
        --skip-package-build)
            SKIP_PACKAGE_BUILD=1
            ;;
        *)
            echo "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

if [[ "$SCAN_APPS" -eq 0 && "$SCAN_PACKAGES" -eq 0 ]]; then
    echo "No scan targets selected. Exiting."
    exit 0
fi

total_warnings=0
scan_failures=0
scan_results="$(mktemp)"
trap 'rm -f "$scan_results"' EXIT

if [[ "$SCAN_PACKAGES" -eq 1 ]]; then
    collect_package_targets

    for package in "${package_targets[@]}"; do
        package_output="$(mktemp)"
        echo "Running Periphery (package): $package"
        if ! scan_package "$package" "$package_output"; then
            echo "  -> scan failed"
            scan_failures=1
            cat "$package_output"
            rm -f "$package_output"
            continue
        fi

        if [[ "$JSON_OUTPUT" -eq 0 ]]; then
            package_warnings=$(grep -Ec '^/.+:[0-9]+:[0-9]+: warning:' "$package_output" || true)
            echo "  -> warnings: $package_warnings"
            total_warnings=$((total_warnings + package_warnings))
            cat "$package_output"
        fi

        [[ "$JSON_OUTPUT" -eq 1 ]] && cat "$package_output" >>"$scan_results"
        rm -f "$package_output"
    done
fi

if [[ "$SCAN_APPS" -eq 1 ]]; then
    collect_app_schemes

    for scheme in "${app_schemes[@]}"; do
        scheme_output="$(mktemp)"
        echo "Running Periphery (app scheme): $scheme"
        if ! scan_scheme "$scheme" "$scheme_output"; then
            echo "  -> scan failed"
            scan_failures=1
            cat "$scheme_output"
            rm -f "$scheme_output"
            continue
        fi

        if [[ "$JSON_OUTPUT" -eq 0 ]]; then
            scheme_warnings=$(grep -Ec '^/.+:[0-9]+:[0-9]+: warning:' "$scheme_output" || true)
            echo "  -> warnings: $scheme_warnings"
            total_warnings=$((total_warnings + scheme_warnings))
            cat "$scheme_output"
        fi

        [[ "$JSON_OUTPUT" -eq 1 ]] && cat "$scheme_output" >>"$scan_results"
        rm -f "$scheme_output"
    done
fi

if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    cat "$scan_results"
    echo "Periphery JSON scan complete."
    if [[ "$scan_failures" -ne 0 ]]; then
        exit 1
    fi
    exit 0
fi

echo ""
if [[ "$scan_failures" -ne 0 ]]; then
    echo "Periphery failed: one or more scans crashed."
    exit 1
fi

if [[ "$total_warnings" -ne 0 ]]; then
    echo "Periphery failed: found $total_warnings warning(s)."
    exit 1
fi

echo "Periphery scan complete."
