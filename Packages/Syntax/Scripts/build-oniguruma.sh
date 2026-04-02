#!/bin/bash
# build-oniguruma.sh
# Builds Oniguruma as a universal static library for macOS (arm64 + x86_64)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PACKAGE_DIR/.onig-build"
OUTPUT_DIR="$PACKAGE_DIR/Sources/COniguruma/lib"

ONIG_VERSION="6.9.9"
ONIG_URL="https://github.com/kkos/oniguruma/releases/download/v${ONIG_VERSION}/onig-${ONIG_VERSION}.tar.gz"

echo "=== Building Oniguruma ${ONIG_VERSION} for macOS ==="
echo "Build directory: $BUILD_DIR"
echo "Output directory: $OUTPUT_DIR"

# Create directories
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

cd "$BUILD_DIR"

# Download if not already present
if [ ! -f "onig-${ONIG_VERSION}.tar.gz" ]; then
    echo "=== Downloading Oniguruma ${ONIG_VERSION} ==="
    curl -L "$ONIG_URL" -o "onig-${ONIG_VERSION}.tar.gz"
fi

# Extract
if [ ! -d "onig-${ONIG_VERSION}" ]; then
    echo "=== Extracting ==="
    tar xzf "onig-${ONIG_VERSION}.tar.gz"
fi

cd "onig-${ONIG_VERSION}"

# Build for arm64
echo "=== Building for arm64 ==="
make clean 2>/dev/null || true
./configure \
    --host=aarch64-apple-darwin \
    --enable-static \
    --disable-shared \
    --prefix="$BUILD_DIR/arm64" \
    CFLAGS="-arch arm64 -O2 -mmacosx-version-min=14.0"
make -j$(sysctl -n hw.ncpu)
make install

# Build for x86_64
echo "=== Building for x86_64 ==="
make clean
./configure \
    --host=x86_64-apple-darwin \
    --enable-static \
    --disable-shared \
    --prefix="$BUILD_DIR/x86_64" \
    CFLAGS="-arch x86_64 -O2 -mmacosx-version-min=14.0"
make -j$(sysctl -n hw.ncpu)
make install

# Create universal binary
echo "=== Creating universal binary ==="
lipo -create \
    "$BUILD_DIR/arm64/lib/libonig.a" \
    "$BUILD_DIR/x86_64/lib/libonig.a" \
    -output "$OUTPUT_DIR/libonig.a"

# Copy header
mkdir -p "$PACKAGE_DIR/Sources/COniguruma/include"
cp "$BUILD_DIR/arm64/include/oniguruma.h" "$PACKAGE_DIR/Sources/COniguruma/include/"

echo "=== Build complete ==="
echo "Static library: $OUTPUT_DIR/libonig.a"
echo "Header: $PACKAGE_DIR/Sources/COniguruma/include/oniguruma.h"

# Verify
echo ""
echo "=== Verification ==="
file "$OUTPUT_DIR/libonig.a"
lipo -info "$OUTPUT_DIR/libonig.a"
