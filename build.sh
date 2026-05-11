#!/bin/bash
set -e

OPENBOR_REPO="${OPENBOR_REPO:-https://github.com/gonzalomvp/openbor.git}"
OPENBOR_BRANCH="${OPENBOR_BRANCH:-v6330-fflns}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"

CROSS=aarch64-linux-gnu

export CC=${CROSS}-gcc
export CXX=${CROSS}-g++
export AR=${CROSS}-ar
export STRIP=${CROSS}-strip
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
make BUILD_LINUX=1 \
    CC=aarch64-linux-gnu-gcc \
    ARCHFLAGS="" \
    BUILD_AMD64=1 \
    SDKPATH=/usr \
    LIBRARIES=/usr/lib/aarch64-linux-gnu \
    -j$(nproc)

cd /build

# ============================================================
# 결과물 수집
# ============================================================
echo "=== Collecting output ==="
mkdir -p "$OUTPUT_DIR"

OPENBOR_BIN=$(find openbor/engine -maxdepth 1 \( -name "OpenBOR" -o -name "OpenBOR.elf" \) -type f | head -1)

if [ -z "$OPENBOR_BIN" ]; then
    echo "ERROR: Binary not found. Contents of engine/:"
    ls -la openbor/engine/
    exit 1
fi

cp "$OPENBOR_BIN" "$OUTPUT_DIR/OpenBOR"
${STRIP} -s "$OUTPUT_DIR/OpenBOR"
echo "Binary: $OPENBOR_BIN -> $OUTPUT_DIR/OpenBOR"

# 아키텍처 확인
${CROSS}-readelf -h "$OUTPUT_DIR/OpenBOR" | grep -E "Class|Machine"

echo "=== ccache stats ==="
ccache --show-stats

echo "=== Build complete ==="
ls -lh "$OUTPUT_DIR/"
