#!/usr/bin/env bash
# Enforce the active design-system contract in shared UI and the mac client.

set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/tooling.sh

RG_BIN="$(resolve_tool_or_die rg)"
TMP_OUTPUT="$(mktemp)"
trap 'rm -f "$TMP_OUTPUT"' EXIT

failures=0

check_fixed_string() {
    local description="$1"
    local needle="$2"
    shift 2
    local paths=("$@")

    if "$RG_BIN" -n --fixed-strings "$needle" "${paths[@]}" >"$TMP_OUTPUT"; then
        echo "Design system gate failed: ${description}" >&2
        cat "$TMP_OUTPUT" >&2
        echo "" >&2
        failures=1
    fi
}

check_regex() {
    local description="$1"
    local pattern="$2"
    shift 2
    local paths=("$@")

    if "$RG_BIN" -n "$pattern" "${paths[@]}" >"$TMP_OUTPUT"; then
        echo "Design system gate failed: ${description}" >&2
        cat "$TMP_OUTPUT" >&2
        echo "" >&2
        failures=1
    fi
}

shared_ui_paths=(
    "Packages/UI/Sources/UI"
    "Apps/mac-client/Sources/mac"
)

active_mac_paths=(
    "Apps/mac-client/Sources/mac"
)

check_fixed_string "obsolete surface helper .surface(...) is banned" ".surface(" "${shared_ui_paths[@]}"
check_fixed_string "obsolete card helper .card(...) is banned" ".card(" "${shared_ui_paths[@]}"
check_fixed_string "obsolete SurfaceLevel type is banned" "SurfaceLevel" "${shared_ui_paths[@]}"
check_fixed_string "obsolete SurfaceModifier type is banned" "SurfaceModifier" "${shared_ui_paths[@]}"
check_fixed_string "obsolete CardModifier type is banned" "CardModifier" "${shared_ui_paths[@]}"
check_regex "ActionButton styles are limited to .primary and .ghost" "style: \\.(secondary|danger)" "${shared_ui_paths[@]}"

check_fixed_string "rounded border text fields are banned in active mac feature code" ".textFieldStyle(.roundedBorder)" "${active_mac_paths[@]}"
check_fixed_string "bordered button styles are banned in active mac feature code" ".buttonStyle(.bordered)" "${active_mac_paths[@]}"
check_fixed_string "raw .system(size:) typography is banned in active mac feature code" ".font(.system(size:" "${active_mac_paths[@]}"

if [[ "$failures" -ne 0 ]]; then
    exit 1
fi

echo "Design system gate passed."
