#!/usr/bin/env bash
# Build GhosttyKit.xcframework from the pinned Ghostty source checkout.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=./lib/ghostty-config.sh
source "$repo_root/scripts/lib/ghostty-config.sh"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/build-ghostty.sh

Builds GhosttyKit.xcframework and Ghostty runtime resources from the pinned
Ghostty source checkout into Vendor/Ghostty/.

Environment:
  ZIG_BIN=/absolute/path/to/zig   Use a specific Zig binary.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

"$repo_root/scripts/bootstrap-ghostty.sh"

zig_bin="${ZIG_BIN:-}"
if [[ -z "$zig_bin" ]]; then
    if command -v zig >/dev/null 2>&1; then
        zig_bin="$(command -v zig)"
    else
        local_zig="$repo_root/$DEVYS_GHOSTTY_TOOLCHAIN_DIR/zig-aarch64-macos-0.15.2/zig"
        if [[ -x "$local_zig" ]]; then
            zig_bin="$local_zig"
        else
            local_zig="$repo_root/$DEVYS_GHOSTTY_TOOLCHAIN_DIR/zig-x86_64-macos-0.15.2/zig"
            if [[ -x "$local_zig" ]]; then
                zig_bin="$local_zig"
            fi
        fi
    fi
fi

if [[ -z "$zig_bin" || ! -x "$zig_bin" ]]; then
    echo "Zig $DEVYS_GHOSTTY_MIN_ZIG_VERSION is required to build Ghostty." >&2
    echo "Run ./scripts/bootstrap-zig.sh or set ZIG_BIN=/absolute/path/to/zig." >&2
    exit 1
fi

zig_version="$("$zig_bin" version)"
if [[ "$zig_version" != "$DEVYS_GHOSTTY_MIN_ZIG_VERSION" ]]; then
    echo "Expected Zig $DEVYS_GHOSTTY_MIN_ZIG_VERSION but found $zig_version." >&2
    echo "Use ./scripts/bootstrap-zig.sh for the pinned toolchain." >&2
    exit 1
fi

source_dir="$repo_root/$DEVYS_GHOSTTY_SOURCE_DIR"
build_root="$repo_root/$DEVYS_GHOSTTY_BUILD_DIR"
install_root="$build_root/install"
global_cache="$build_root/zig-global-cache"
local_cache="$build_root/zig-local-cache"
artifact_dir="$repo_root/$DEVYS_GHOSTTY_XCFRAMEWORK_DIR"
resources_dir="$repo_root/$DEVYS_GHOSTTY_RESOURCES_DIR"

rm -rf "$install_root"
mkdir -p "$build_root"

(
    cd "$source_dir"
    env \
        ZIG_GLOBAL_CACHE_DIR="$global_cache" \
        ZIG_LOCAL_CACHE_DIR="$local_cache" \
        "$zig_bin" build \
            --prefix "$install_root" \
            -Doptimize="$DEVYS_GHOSTTY_BUILD_MODE" \
            -Demit-xcframework=true \
            -Demit-macos-app=false \
            -Dxcframework-target="$DEVYS_GHOSTTY_XCFRAMEWORK_TARGET"
)

staged_xcframework="$source_dir/macos/GhosttyKit.xcframework"
staged_resources="$install_root/share/ghostty"

if [[ ! -d "$staged_xcframework" ]]; then
    echo "Ghostty xcframework missing from install root: $staged_xcframework" >&2
    exit 1
fi

if [[ ! -d "$staged_resources" ]]; then
    echo "Ghostty runtime resources missing from install root: $staged_resources" >&2
    exit 1
fi

mkdir -p "$(dirname "$artifact_dir")" "$(dirname "$resources_dir")"
rm -rf "$artifact_dir" "$resources_dir"
cp -R "$staged_xcframework" "$artifact_dir"
cp -R "$staged_resources" "$resources_dir"

echo "Ghostty build complete:"
echo "  xcframework: $artifact_dir"
echo "  resources:   $resources_dir"
