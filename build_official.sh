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
# ccache 설정
export CCACHE_DIR="${CCACHE_DIR:-/ccache}"
export PATH="/usr/lib/ccache:$PATH"
ln -sf /usr/bin/ccache /usr/local/bin/${CROSS}-gcc
ln -sf /usr/bin/ccache /usr/local/bin/${CROSS}-g++
ccache --max-size=1G
ccache --zero-stats
# ============================================================
# 소스 클론
# ============================================================
echo "=== Cloning OpenBOR (branch: ${OPENBOR_BRANCH}) ==="
git clone --depth=1 --branch "$OPENBOR_BRANCH" "$OPENBOR_REPO" openbor
cd openbor/engine
# ============================================================
# 빌드
# ============================================================
echo "=== Building OpenBOR for aarch64 ==="

[ -f version.sh ] && bash version.sh
make BUILD_LINUX=1 \
    CC=${CROSS}-gcc \
    GCC_TARGET=aarch64-linux-gnu \
    NO_STRIP=1 \
    SDKPATH=/usr \
    -j$(nproc)

# strip
${CROSS}-strip OpenBOR.elf -o OpenBOR
cd /build
# ============================================================
# 결과물 수집
# ============================================================
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
# ============================================================
# 공유 라이브러리 수집 (YabaSanshiro 패턴)
# 기기에 기본 탑재된 라이브러리는 제외, 없을 수 있는 것만 포함
# ============================================================
# 기기 제공 라이브러리 — 번들 제외 목록
SKIP_LIBS="linux-vdso|ld-linux|libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so|libgcc_s|libstdc\+\+|libasound|libudev|libdrm|libwayland|libEGL|libGLES|libMali|libgomp|libvulkan|libGL\.so|libGLX|libGLdispatch"
collect_deps() {
    local binary="$1"
    ${CROSS}-readelf -d "$binary" 2>/dev/null | grep NEEDED | sed 's/.*\[\(.*\)\]/\1/' | while read -r lib; do
        # 이미 수집한 것 건너뜀
        [ -f "$OUTPUT_DIR/libs/$lib" ] && continue
        # 제외 목록 건너뜀
        echo "$lib" | grep -qE "$SKIP_LIBS" && continue
        local src
        src=$(find "/usr/lib/${CROSS}" "/lib/${CROSS}" -maxdepth 1 -name "$lib" 2>/dev/null | head -1)
        if [ -n "$src" ]; then
            cp -L "$src" "$OUTPUT_DIR/libs/$lib"
            echo "  Collected: $lib"
            # 재귀적으로 의존성 수집
            collect_deps "$OUTPUT_DIR/libs/$lib"
        else
            echo "  WARNING: $lib not found"
        fi
    done
}
echo "=== Collecting shared library dependencies ==="
collect_deps "$OUTPUT_DIR/OpenBOR"
# 수집된 lib들의 의존성도 재귀 수집
for lib in "$OUTPUT_DIR"/libs/*.so*; do
    [ -f "$lib" ] && collect_deps "$lib"
done
# 수집된 라이브러리 strip
for so in "$OUTPUT_DIR"/libs/*.so*; do
    ${CROSS}-strip -s "$so" 2>/dev/null || true
done
echo "=== ccache stats ==="
ccache --show-stats
echo "=== Build complete ==="
ls -lh "$OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR/libs/" 2>/dev/null || true
