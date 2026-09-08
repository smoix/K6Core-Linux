FROM ubuntu:22.04

# Avoid interactive prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install all standard Buildroot compilation dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    bash \
    bc \
    binutils \
    bzip2 \
    cpio \
    g++ \
    gcc \
    git \
    gzip \
    locales \
    libncurses-dev \
    libssl-dev \
    make \
    patch \
    perl \
    python3 \
    rsync \
    sed \
    tar \
    unzip \
    wget \
    file \
    && rm -rf /var/lib/apt/lists/*

# Configure en_US.UTF-8 locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Download and extract stable Buildroot 2025.02.1
ENV BUILDROOT_VERSION=2025.02.1
RUN wget https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.xz \
    && tar -xf buildroot-${BUILDROOT_VERSION}.tar.xz \
    && mv buildroot-${BUILDROOT_VERSION} /buildroot \
    && rm buildroot-${BUILDROOT_VERSION}.tar.xz

# Bump xterm from Buildroot's pinned 389 to 411: 389 has a known musl-libc bug
# (its manual posix_openpt/grantpt/unlockpt pty setup fails with "open ttydev:
# I/O error" -- Gentoo bug 689080), fixed upstream in patch #391.
RUN sed -i \
    -e 's/^XTERM_VERSION = 389$/XTERM_VERSION = 411/' \
    /buildroot/package/xterm/xterm.mk \
    && printf 'sha256  969be283670deadd66934865c4de6c5ab045e3a3facc2b228decf91a20d8c36c  xterm-411.tgz\nsha256  f272fa007de2cffdb22b4df09e9a3aaec3555d5a6913229b70006ee137ab22b5  COPYING\n' > /buildroot/package/xterm/xterm.hash

# Force unsafe configure (allows compiling as root user inside Docker container)
ENV FORCE_UNSAFE_CONFIGURE=1

WORKDIR /workspace
