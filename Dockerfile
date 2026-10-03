# syntax=docker/dockerfile:1
FROM ubuntu:20.04 as builder

# Avoid prompts from apt
ARG DEBIAN_FRONTEND=noninteractive

# Install necessary packages for PS2DEV, VCLPP and VCL
RUN apt-get update && apt-get install -y --no-install-recommends \
    git make g++ texinfo bison flex gettext libgmp3-dev \
    libmpfr-dev libmpc-dev gcc binutils cmake wget patch zlib1g-dev libgsl-dev \
    unzip curl build-essential ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Setup PS2DEV environment variables
ENV PS2DEV=/usr/local/ps2dev
RUN mkdir -p $PS2DEV
ENV PS2SDK=$PS2DEV/ps2sdk
ENV GSKIT=$PS2DEV/gsKit
ENV PATH=$PATH:${PS2DEV}/bin:${PS2DEV}/ee/bin:${PS2DEV}/iop/bin:${PS2DEV}/dvp/bin:${PS2SDK}/bin

# Compile PS2DEV (utilizing all available CPU cores for speed)
RUN mkdir -p /temp/ps2dev && \
    git clone --depth 1 https://github.com/ps2dev/ps2dev.git /temp/ps2dev
WORKDIR /temp/ps2dev
RUN ./build-all.sh -j$(nproc)

# Compile VCLPP
RUN mkdir -p /temp/vclpp && \
    git clone --depth 1 https://github.com/glampert/vclpp.git /temp/vclpp
WORKDIR /temp/vclpp
RUN make -j$(nproc)

# Download VCL
RUN mkdir -p /temp/vcl
WORKDIR /temp/vcl
RUN wget -q https://github.com/h4570/tyra/raw/master/assets/vcl

# ------------------------------------------------------------------------------

# Final stage
FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive

# Set ENV variables
ENV PS2DEV=/usr/local/ps2dev
ENV PS2SDK=$PS2DEV/ps2sdk
ENV PATH=$PATH:${PS2DEV}/bin:${PS2DEV}/ee/bin:${PS2DEV}/iop/bin:${PS2DEV}/dvp/bin:${PS2SDK}/bin

# Copy compiled toolchains from builder stage
COPY --from=builder ${PS2DEV} ${PS2DEV}
COPY --from=builder /temp/vcl/vcl /usr/bin/vcl
COPY --from=builder /temp/vclpp/vclpp /usr/bin/vclpp

# Install runtime packages for emulation, SCons, and build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    make rsync libmpc-dev qemu qemu-user-static binfmt-support psmisc \
    pkg-config python3 python3-pip ca-certificates && \
    python3 -m pip install --no-cache-dir scons && \
    rm -rf /var/lib/apt/lists/*

# Add 32-bit executable support for VCL tools
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends libstdc++5:i386 && \
    rm -rf /var/lib/apt/lists/*

RUN update-binfmts --install i386 /usr/bin/qemu-i386-static \
    --magic '\x7fELF\x01\x01\x01\x03\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\x03\x00\x01\x00\x00\x00' \
    --mask '\xff\xff\xff\xff\xff\xff\xff\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xf8\xff\xff\xff\xff\xff\xff\xff' || true

# Set correct permissions
RUN chmod 755 /usr/bin/vclpp && \
    chmod 755 /usr/bin/vcl

# Copy the entire Godot workspace context into the container
COPY . /godot

WORKDIR /godot
CMD ["/bin/bash"]