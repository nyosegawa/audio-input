#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$PROJECT_DIR/vendor/whisper"
WHISPER_VERSION="v1.8.3"
STAMP_FILE="$VENDOR_DIR/.version"

# Skip if already built at the correct version
if [ -f "$STAMP_FILE" ] && [ "$(cat "$STAMP_FILE")" = "$WHISPER_VERSION" ]; then
    echo "=== whisper.cpp $WHISPER_VERSION already built ==="
    exit 0
fi

echo "=== Building whisper.cpp $WHISPER_VERSION ==="

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Clone
echo "Cloning whisper.cpp..."
git clone --depth 1 --branch "$WHISPER_VERSION" https://github.com/ggml-org/whisper.cpp.git "$TMPDIR/whisper.cpp" 2>&1

# Build with cmake
echo "Configuring cmake..."
cmake -B "$TMPDIR/whisper.cpp/build" -S "$TMPDIR/whisper.cpp" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    2>&1

echo "Building..."
cmake --build "$TMPDIR/whisper.cpp/build" --config Release -j$(sysctl -n hw.ncpu) 2>&1

# Install
echo "Installing to $VENDOR_DIR..."
mkdir -p "$VENDOR_DIR/lib" "$VENDOR_DIR/include"

# Combine all static libraries
libtool -static -o "$VENDOR_DIR/lib/libwhisper.a" \
    "$TMPDIR/whisper.cpp/build/src/libwhisper.a" \
    "$TMPDIR/whisper.cpp/build/ggml/src/libggml.a" \
    "$TMPDIR/whisper.cpp/build/ggml/src/libggml-base.a" \
    "$TMPDIR/whisper.cpp/build/ggml/src/libggml-cpu.a" \
    "$TMPDIR/whisper.cpp/build/ggml/src/ggml-metal/libggml-metal.a" \
    "$TMPDIR/whisper.cpp/build/ggml/src/ggml-blas/libggml-blas.a" \
    2>&1

# Copy headers
cp "$TMPDIR/whisper.cpp/include/whisper.h" "$VENDOR_DIR/include/"
cp "$TMPDIR/whisper.cpp/ggml/include/"*.h "$VENDOR_DIR/include/"

# Also copy to CWhisper include for module map
CWHISPER_INCLUDE="$PROJECT_DIR/Dependencies/CWhisper/include"
mkdir -p "$CWHISPER_INCLUDE"
cp "$VENDOR_DIR/include/"*.h "$CWHISPER_INCLUDE/"

# Version stamp
echo "$WHISPER_VERSION" > "$STAMP_FILE"

echo "=== whisper.cpp $WHISPER_VERSION built successfully ==="
ls -lh "$VENDOR_DIR/lib/libwhisper.a"
