#!/usr/bin/env bash
# Builds libghostty-vt at the pinned revision (vendor/ghostty/VERSION) for the native terminal
# (GhosttyVT.xcframework: macOS arm64, iOS arm64, iOS simulator arm64) and the web terminal
# (ghostty-vt.wasm), and stages both. The artifacts are committed, so an ordinary build needs
# no Zig; run this only to move the pin.   bun run ghostty:build
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
revision="$(tr -d '[:space:]' < "$root/vendor/ghostty/VERSION")"
zig_version="0.15.2"
source_dir="${GHOSTTY_SOURCE_DIR:-$HOME/.cache/devys/ghostty-${revision:0:8}}"
framework="$root/apple/Packages/DevysTerminal/Vendor/GhosttyVT.xcframework"
shim_headers="$root/apple/Packages/DevysTerminal/Sources/CGhosttyVT/include"
web="$root/src/surfaces/terminal/vendor"

log() { printf '[ghostty] %s\n' "$*"; }
die() { printf '[ghostty] error: %s\n' "$*" >&2; exit 1; }

command -v zig >/dev/null && [[ "$(zig version)" == "$zig_version" ]] || die "Zig $zig_version is required"

if [[ ! -d "$source_dir/.git" ]]; then
  log "cloning Ghostty"
  git clone --filter=blob:none --no-checkout https://github.com/ghostty-org/ghostty.git "$source_dir"
fi
if [[ "$(git -C "$source_dir" rev-parse HEAD 2>/dev/null || echo none)" != "$revision" ]]; then
  git -C "$source_dir" fetch --depth=1 origin "$revision"
  git -C "$source_dir" checkout --detach "$revision"
fi

# Only the static library is used. On Apple targets the shared library needs Zig's bundled
# libc++, which Zig 0.15.2 cannot compile against the macOS 27 SDK (`INFINITY` undeclared), so
# the checkout used here skips installing it there.
git -C "$source_dir" checkout -- build.zig
perl -0pi -e 's/    libghostty_vt_shared\.install\(b\.getInstallStep\(\)\);/    if (!config.target.result.os.tag.isDarwin()) libghostty_vt_shared.install(b.getInstallStep());/' "$source_dir/build.zig"
grep -q "isDarwin()) libghostty_vt_shared.install" "$source_dir/build.zig" || die "could not skip the shared library"

build_root="$(mktemp -d)"
trap 'rm -rf "$build_root"' EXIT

# One static library per Apple slice: libghostty-vt plus the archives it depends on.
apple_slice() {
  local target="$1" name="$2" cpu="${3:-baseline}" install="$build_root/$2" cache="$build_root/$2-cache"
  log "building $target"
  (cd "$source_dir" && ZIG_LOCAL_CACHE_DIR="$cache" ZIG_GLOBAL_CACHE_DIR="$build_root/global" \
    zig build --prefix "$install" -Demit-lib-vt=true -Demit-xcframework=false -Doptimize=ReleaseFast -Dtarget="$target" -Dcpu="$cpu" \
    -Dlib-version-string="0.1.0-dev+$revision")
  local parts=("$install/lib/libghostty-vt.a")
  while IFS= read -r archive; do parts+=("$archive"); done < <(find "$cache" \( -name 'libsimdutf.a' -o -name 'libhighway.a' \))
  mkdir -p "$build_root/$name"
  xcrun libtool -static -o "$build_root/$name/libghostty-vt.a" "${parts[@]}" 2>/dev/null
}
apple_slice aarch64-macos macos-arm64
apple_slice aarch64-ios ios-arm64
# The simulator rejects the generic CPU model; Ghostty's own Apple build forces this one too.
apple_slice aarch64-ios-simulator ios-arm64-simulator apple_a17

# The libraries carry no headers; the CGhosttyVT shim target exposes them as a Clang module.
rm -rf "$shim_headers/ghostty"
cp -R "$source_dir/include/ghostty" "$shim_headers/ghostty"
rm -rf "$framework"
mkdir -p "$(dirname "$framework")"
xcodebuild -create-xcframework \
  -library "$build_root/macos-arm64/libghostty-vt.a" \
  -library "$build_root/ios-arm64/libghostty-vt.a" \
  -library "$build_root/ios-arm64-simulator/libghostty-vt.a" \
  -output "$framework" >/dev/null

log "building wasm32-freestanding"
(cd "$source_dir" && zig build -Demit-lib-vt -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall -Dstrip=true \
  -Dlib-version-string="0.1.0-dev+$revision" -p "$build_root/wasm")
mkdir -p "$web"
cp "$build_root/wasm/bin/ghostty-vt.wasm" "$web/ghostty-vt.wasm"
zig build-exe "$root/scripts/ghostty-write-pty.zig" -target wasm32-freestanding -O ReleaseSmall -fno-entry -rdynamic \
  -femit-bin="$web/ghostty-write-pty.wasm"
rm -f "$web"/*.o
cp "$source_dir/LICENSE" "$root/vendor/ghostty/LICENSE"
log "pinned $revision: $framework and $web"
