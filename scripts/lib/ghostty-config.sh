#!/usr/bin/env bash

readonly DEVYS_GHOSTTY_REPOSITORY="https://github.com/ghostty-org/ghostty.git"
readonly DEVYS_GHOSTTY_COMMIT="48d3e972d839999745368b156df396d9512fd17b"
readonly DEVYS_GHOSTTY_VERSION="1.3.2-dev"
readonly DEVYS_GHOSTTY_MIN_ZIG_VERSION="0.15.2"

readonly DEVYS_GHOSTTY_SOURCE_DIR=".deps/ghostty-src"
readonly DEVYS_GHOSTTY_BUILD_DIR=".deps/ghostty-build"
readonly DEVYS_GHOSTTY_TOOLCHAIN_DIR=".deps/tools"

readonly DEVYS_GHOSTTY_BUILD_MODE="ReleaseFast"
readonly DEVYS_GHOSTTY_XCFRAMEWORK_TARGET="universal"
readonly DEVYS_GHOSTTY_XCFRAMEWORK_DIR="Vendor/Ghostty/GhosttyKit.xcframework"
readonly DEVYS_GHOSTTY_RESOURCES_DIR="Vendor/Ghostty/share/ghostty"

readonly DEVYS_GHOSTTY_ZIG_AARCH64_MACOS_URL="https://ziglang.org/download/0.15.2/zig-aarch64-macos-0.15.2.tar.xz"
readonly DEVYS_GHOSTTY_ZIG_AARCH64_MACOS_SHA256="3cc2bab367e185cdfb27501c4b30b1b0653c28d9f73df8dc91488e66ece5fa6b"
readonly DEVYS_GHOSTTY_ZIG_X86_64_MACOS_URL="https://ziglang.org/download/0.15.2/zig-x86_64-macos-0.15.2.tar.xz"
readonly DEVYS_GHOSTTY_ZIG_X86_64_MACOS_SHA256="375b6909fc1495d16fc2c7db9538f707456bfc3373b14ee83fdd3e22b3d43f7f"
