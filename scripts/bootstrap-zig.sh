#!/usr/bin/env bash
# Install the pinned Zig toolchain locally for Ghostty builds.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=./lib/ghostty-config.sh
source "$repo_root/scripts/lib/ghostty-config.sh"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/bootstrap-zig.sh

Installs Zig 0.15.2 into .deps/tools if it is not already present.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

arch="$(uname -m)"
platform_dir=""
archive_url=""
archive_sha256=""
archive_name=""

case "$arch" in
    arm64)
        platform_dir="zig-aarch64-macos-0.15.2"
        archive_url="$DEVYS_GHOSTTY_ZIG_AARCH64_MACOS_URL"
        archive_sha256="$DEVYS_GHOSTTY_ZIG_AARCH64_MACOS_SHA256"
        archive_name="zig-aarch64-macos-0.15.2.tar.xz"
        ;;
    x86_64)
        platform_dir="zig-x86_64-macos-0.15.2"
        archive_url="$DEVYS_GHOSTTY_ZIG_X86_64_MACOS_URL"
        archive_sha256="$DEVYS_GHOSTTY_ZIG_X86_64_MACOS_SHA256"
        archive_name="zig-x86_64-macos-0.15.2.tar.xz"
        ;;
    *)
        echo "Unsupported architecture for local Zig bootstrap: $arch" >&2
        exit 1
        ;;
esac

install_root="$repo_root/$DEVYS_GHOSTTY_TOOLCHAIN_DIR"
install_dir="$install_root/$platform_dir"
zig_bin="$install_dir/zig"

if [[ -x "$zig_bin" ]]; then
    echo "$zig_bin"
    exit 0
fi

mkdir -p "$install_root"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

archive_path="$tmp_dir/$archive_name"

curl -fsSL "$archive_url" -o "$archive_path"
echo "$archive_sha256  $archive_path" | shasum -a 256 -c -
tar -C "$tmp_dir" -xf "$archive_path"
rm -rf "$install_dir"
mv "$tmp_dir/$platform_dir" "$install_dir"

echo "$zig_bin"
