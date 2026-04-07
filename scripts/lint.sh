#!/usr/bin/env bash
# Run SwiftLint on all apps/packages or explicitly provided paths.
# Usage:
#   ./scripts/lint.sh                     # Run against all Apps/* + Packages/*
#   ./scripts/lint.sh path1 path2 ...      # Lint specific paths (apps/packages)
#   ./scripts/lint.sh --fix path1 path2 ... # Autocorrect + format specific paths

set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/tooling.sh

SWIFTLINT_BIN="$(resolve_tool_or_die swiftlint)"

TARGETS=()
FIX_MODE=0
LINT_FAILED=0
SWIFTLINT_CONFIG=".swiftlint.yml"

collect_default_targets() {
    local discovered=( )
    local package_manifest
    local app_dir
    local app_name

    for package_manifest in Packages/*/Package.swift; do
        [[ -f "$package_manifest" ]] || continue
        discovered+=("${package_manifest%/Package.swift}")
    done

    for app_dir in Apps/*; do
        [[ -d "$app_dir" ]] || continue
        app_name="$(basename "$app_dir")"
        [[ "$app_name" == _* ]] && continue
        discovered+=("$app_dir")
    done

    printf '%s\n' "${discovered[@]}" | sort
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix)
            FIX_MODE=1
            ;;
        --help|-h)
            cat <<'EOF'
Usage:
  ./scripts/lint.sh                     # Run SwiftLint (strict) across all apps/packages
  ./scripts/lint.sh --fix              # Autocorrect + format all apps/packages
  ./scripts/lint.sh <path> [path...]   # Lint provided paths
  ./scripts/lint.sh --fix <path> ...   # Autocorrect provided paths
EOF
            exit 0
            ;;
        *)
            TARGETS+=("$1")
            ;;
    esac
    shift
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    while IFS= read -r target; do
        TARGETS+=("$target")
    done < <(collect_default_targets)
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "No lint targets found. Exiting."
    exit 1
fi

if [[ "$FIX_MODE" -eq 1 ]]; then
    echo "Running SwiftLint with autocorrect..."
else
    echo "Running SwiftLint in strict mode..."
fi

for target in "${TARGETS[@]}"; do
    if [[ ! -e "$target" ]]; then
        echo "Skipping missing path: $target"
        continue
    fi

    echo " -> $target"
    if [[ "$FIX_MODE" -eq 1 ]]; then
        if ! env \
            -u SWIFT_DEBUG_INFORMATION_FORMAT \
            -u SWIFT_DEBUG_INFORMATION_VERSION \
            "$SWIFTLINT_BIN" lint --config "$SWIFTLINT_CONFIG" --fix --format "$target"; then
            LINT_FAILED=1
        fi
    else
        if ! env \
            -u SWIFT_DEBUG_INFORMATION_FORMAT \
            -u SWIFT_DEBUG_INFORMATION_VERSION \
            "$SWIFTLINT_BIN" lint --config "$SWIFTLINT_CONFIG" --strict "$target"; then
            LINT_FAILED=1
        fi
    fi
done

echo ""
echo "SwiftLint complete."

if [[ "$LINT_FAILED" -ne 0 ]]; then
    exit 1
fi
