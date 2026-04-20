#!/usr/bin/env bash
# Build and stage libghostty-vt static libraries for the repo's Apple targets.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=./lib/ghostty-config.sh
source "$repo_root/scripts/lib/ghostty-config.sh"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/build-ghostty-vt.sh

Builds libghostty-vt for the repo's Apple targets and stages the resulting
headers and static libraries into Vendor/Ghostty/libghostty-vt/.

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
    echo "Zig $DEVYS_GHOSTTY_MIN_ZIG_VERSION is required to build libghostty-vt." >&2
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
build_root="$repo_root/$DEVYS_GHOSTTY_BUILD_DIR/libghostty-vt"
artifact_root="$repo_root/$DEVYS_GHOSTTY_VT_ARTIFACT_DIR"
package_include_root="$repo_root/Packages/GhosttyTerminal/Sources/CGhosttyVT/include"

build_target() {
    local zig_target="$1"
    local stage_name="$2"
    local install_root="$build_root/$stage_name/install"
    local global_cache="$build_root/$stage_name/zig-global-cache"
    local local_cache="$build_root/$stage_name/zig-local-cache"
    local simdutf_lib
    local highway_lib

    rm -rf "$install_root"
    mkdir -p "$install_root"

    (
        cd "$source_dir"
        env \
            ZIG_GLOBAL_CACHE_DIR="$global_cache" \
            ZIG_LOCAL_CACHE_DIR="$local_cache" \
            "$zig_bin" build \
                --prefix "$install_root" \
                -Demit-lib-vt=true \
                -Doptimize="$DEVYS_GHOSTTY_BUILD_MODE" \
                -Dtarget="$zig_target"
    )

    if [[ ! -f "$install_root/lib/libghostty-vt.a" ]]; then
        echo "libghostty-vt.a missing for $stage_name." >&2
        exit 1
    fi

    mkdir -p "$artifact_root/$stage_name/lib"
    cp "$install_root/lib/libghostty-vt.a" "$artifact_root/$stage_name/lib/libghostty-vt.a"

    simdutf_lib="$(find "$local_cache" -name 'libsimdutf.a' -print -quit)"
    highway_lib="$(find "$local_cache" -name 'libhighway.a' -print -quit)"

    if [[ -z "$simdutf_lib" || -z "$highway_lib" ]]; then
        echo "libghostty-vt dependency archives missing for $stage_name." >&2
        exit 1
    fi

    cp "$simdutf_lib" "$artifact_root/$stage_name/lib/libsimdutf.a"
    cp "$highway_lib" "$artifact_root/$stage_name/lib/libhighway.a"

    if [[ ! -d "$artifact_root/include" ]]; then
        cp -R "$install_root/include" "$artifact_root/include"
    fi
}

rm -rf "$artifact_root"
mkdir -p "$build_root" "$artifact_root"

build_target "aarch64-macos" "macos-arm64"
build_target "aarch64-ios" "ios-arm64"

rm -rf "$package_include_root/ghostty"
cp -R "$artifact_root/include/ghostty" "$package_include_root/ghostty"

echo "libghostty-vt build complete:"
echo "  headers: $artifact_root/include"
echo "  macOS:   $artifact_root/macos-arm64/lib/libghostty-vt.a"
echo "  iOS:     $artifact_root/ios-arm64/lib/libghostty-vt.a"
echo "  package: $package_include_root/ghostty"
