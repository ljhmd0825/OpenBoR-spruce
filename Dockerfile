FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# Configure multiarch for arm64 cross-compilation (glibc 2.31)
RUN dpkg --add-architecture arm64 && \
    sed -i 's/^deb http/deb [arch=amd64] http/g' /etc/apt/sources.list && \
    echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports focal main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports focal-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        # Build Host Tools
        build-essential \
        gcc-aarch64-linux-gnu \
        g++-aarch64-linux-gnu \
        binutils-aarch64-linux-gnu \
        pkg-config \
        git \
        ca-certificates \
        ccache \
        nasm \
        # OpenBOR arm64 cross-compile dependencies
        libsdl2-dev:arm64 \
        libsdl2-gfx-dev:arm64 \
        libpng-dev:arm64 \
        zlib1g-dev:arm64 \
        libvorbis-dev:arm64 \
        libogg-dev:arm64 \
        libvpx-dev:arm64 \
        libasound2-dev:arm64 \
        libpthread-stubs0-dev:arm64 \
        && rm -rf /var/lib/apt/lists/*

COPY build.sh /build.sh
RUN chmod +x /build.sh

WORKDIR /build

ENTRYPOINT ["/build.sh"]
