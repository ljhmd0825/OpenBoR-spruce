#!/bin/bash
set -e
OPENBOR_REPO="${OPENBOR_REPO:-https://github.com/DCurrent/openbor.git}"
OPENBOR_BRANCH="${OPENBOR_BRANCH:-v7533}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
CROSS=aarch64-linux-gnu
export CC=${CROSS}-gcc
export CXX=${CROSS}-g++
export AR=${CROSS}-ar
export PKG_CONFIG_PATH=/usr/lib/${CROSS}/pkgconfig
export PKG_CONFIG_LIBDIR=/usr/lib/${CROSS}/pkgconfig

# ccache setup
export CCACHE_DIR="${CCACHE_DIR:-/ccache}"
export PATH="/usr/lib/ccache:$PATH"
ln -sf /usr/bin/ccache /usr/local/bin/${CROSS}-gcc
ln -sf /usr/bin/ccache /usr/local/bin/${CROSS}-g++
ccache --max-size=1G
ccache --zero-stats

# Clone

echo "=== Cloning OpenBOR (branch: ${OPENBOR_BRANCH}) ==="
git clone --depth=1 --branch "$OPENBOR_BRANCH" "$OPENBOR_REPO" openbor

# Apply patches
echo "=== Applying patches ==="

# Apply common patches
cd openbor
for patch in /patches/common/*.py; do
    [ -f "$patch" ] && python3 "$patch" && echo "Applied: $(basename $patch)"
done
for patch in /patches/common/*.patch; do
    [ -f "$patch" ] && patch -p1 < "$patch" && echo "Applied: $(basename $patch)"
done

# Apply 64-bit-specific patches
for patch in /patches/official/*.py; do
    [ -f "$patch" ] && python3 "$patch" && echo "Applied: $(basename $patch)"
done
for patch in /patches/official/*.patch; do
    [ -f "$patch" ] && patch -p1 < "$patch" && echo "Applied: $(basename $patch)"
done

# Building

echo "=== Building OpenBOR for aarch64 ==="
cd engine
[ -f version.sh ] && bash version.sh
sed -i 's/vorbis_fpu_control fpu;/\/\/vorbis_fpu_control fpu;/' source/webmlib/samplecvt.c
make BUILD_LINUX=1 \
    CC=${CROSS}-gcc \
    GCC_TARGET=aarch64-linux-gnu \
    ARCHFLAGS="" \
    NO_STRIP=1 \
    SDKPATH=/usr \
    LIBRARIES=/usr/lib/${CROSS} \
    EXTRA_CFLAGS="-Wno-error=unused-variable" \
    -j$(nproc)

# strip
${CROSS}-strip OpenBOR.elf -o OpenBOR
cd /build

# Output

echo "=== Collecting output ==="
mkdir -p "$OUTPUT_DIR/libs"
OPENBOR_BIN=$(find openbor/engine -maxdepth 1 -name "OpenBOR" -type f | head -1)
if [ -z "$OPENBOR_BIN" ]; then
    echo "ERROR: Binary not found."
    ls -la openbor/engine/
    exit 1
fi
cp "$OPENBOR_BIN" "$OUTPUT_DIR/OpenBOR"
echo "Binary: $OPENBOR_BIN -> $OUTPUT_DIR/OpenBOR"

# Collect shared library dependencies
# Skip device-provided libs (SDL2, GLES, EGL, Mali, ALSA, udev, etc.)
SKIP_LIBS="linux-vdso|ld-linux|libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so|libgcc_s|libstdc\+\+|libasound|libudev|libdrm|libwayland|libEGL|libGLES|libMali|libgomp|libvulkan|libGL\.so|libGLX|libGLdispatch"
collect_deps() {
    local binary="$1"
    ${CROSS}-readelf -d "$binary" 2>/dev/null | grep NEEDED | sed 's/.*\[\(.*\)\]/\1/' | while read -r lib; do
        [ -f "$OUTPUT_DIR/libs/$lib" ] && continue
        echo "$lib" | grep -qE "$SKIP_LIBS" && continue
        local src
        src=$(find "/usr/lib/${CROSS}" "/lib/${CROSS}" -maxdepth 1 -name "$lib" 2>/dev/null | head -1)
        if [ -n "$src" ]; then
            cp -L "$src" "$OUTPUT_DIR/libs/$lib"
            echo "  Collected: $lib"
            collect_deps "$OUTPUT_DIR/libs/$lib"
        else
            echo "  WARNING: $lib not found"
        fi
    done
}
echo "=== Collecting shared library dependencies ==="
collect_deps "$OUTPUT_DIR/OpenBOR"
for lib in "$OUTPUT_DIR"/libs/*.so*; do
    [ -f "$lib" ] && collect_deps "$lib"
done
for so in "$OUTPUT_DIR"/libs/*.so*; do
    ${CROSS}-strip -s "$so" 2>/dev/null || true
done
echo "=== ccache stats ==="
ccache --show-stats
echo "=== Build complete ==="
ls -lh "$OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR/libs/" 2>/dev/null || true
