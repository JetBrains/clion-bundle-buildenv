# Ubuntu-based image with xPack mingw-w64 GCC for building the GCC 15
# MinGW toolchain itself. Used ONLY by the MingwToolchain build, which
# compiles binutils/make/gcc — pure C; no C++ standard library.
#
# Other mingw-w64 builds (gdb, lldb, runtime DLLs) need posix-threaded
# host mingw and use mingw.Dockerfile / pkgbuild-mingw.

FROM ubuntu:24.04

ENV LANG=C.UTF-8

RUN groupadd -r --gid 1001 build \
 && useradd --no-log-init --create-home -g build -r --uid 1001 build \
 && mkdir -p /etc/sudoers.d \
 && echo "build ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/build \
 && chmod 0440 /etc/sudoers.d/build

# some of Development Tools (build-essential)
RUN apt-get update \
 && apt-get -y install \
      autoconf \
      automake \
      autopoint \
      binutils \
      bison \
      flex \
      gcc \
      g++ \
      gettext \
      libtool \
      make \
      patch \
      pkg-config \
 && apt-get -y install \
      curl \
      elfutils \
      file \
      git \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# xPack GCC 14.3 cross-compiler instead of Ubuntu's GCC 13-based packages.
# Ubuntu 24.04 ships gcc-mingw-w64 based on GCC 13, which cannot compile
# GCC 15's libgcc (missing __builtin_stack_address, newer cpuid.h constants).
# xPack 14.3 is win32-threaded — fine here because the toolchain build
# compiles only C (binutils, make, gcc), no C++ that touches std::mutex.
ARG XPACK_MINGW_GCC_VERSION=14.3.0-1
ARG XPACK_MINGW_GCC_SHA256=7679c2f81dfb564479f7158dc99751fe03efd3ce03dbfd8372f1e0feb21fcfd4
RUN curl -fsSL -o /tmp/xpack-mingw.tar.gz \
      "https://github.com/xpack-dev-tools/mingw-w64-gcc-xpack/releases/download/v${XPACK_MINGW_GCC_VERSION}/xpack-mingw-w64-gcc-${XPACK_MINGW_GCC_VERSION}-linux-x64.tar.gz" \
 && echo "${XPACK_MINGW_GCC_SHA256}  /tmp/xpack-mingw.tar.gz" | sha256sum -c - \
 && tar xzf /tmp/xpack-mingw.tar.gz -C /opt/ \
 && rm /tmp/xpack-mingw.tar.gz
ENV PATH="/opt/xpack-mingw-w64-gcc-${XPACK_MINGW_GCC_VERSION}/bin:${PATH}"

RUN apt-get update \
 && apt-get -y install \
      libarchive-tools \
      bzip2 \
      chrpath \
      fakeroot \
      libgettextpo-dev \
      gperf \
      libarchive-dev \
      openssl \
      sudo \
      texinfo \
      xz-utils \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# makepkg has /usr/lib/ccache/bin directory hardcoded;
# on Ubuntu, ccache wrappers are already in /usr/lib/ccache/
RUN apt-get update \
 && apt-get -y install \
      ccache \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && cd /usr/lib/ccache && ln -s . bin

COPY assets/ /tmp/build-prerequisites
RUN chmod a+x /tmp/build-prerequisites/*.sh \
 && /tmp/build-prerequisites/install-pacman.sh \
 && rm -rf /tmp/build-prerequisites

RUN mkdir -p /win /workdir \
 && chown build:build /win /workdir

USER build
WORKDIR /workdir
