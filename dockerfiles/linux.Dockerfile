# Centos-based image with makepkg and devtoolset-10 for building PKGBUILD packages.

FROM centos:7

# devtoolset-11 is not avalable for aarch64 centos-7
ARG DEVTOOLSET_VERSION=10

COPY assets/util.sh /tmp/util.sh

# fix repos and install devtoolset
RUN /tmp/util.sh switch_centos_to_vault_repos \
    && yum -y update \
    && yum -y install centos-release-scl-rh \
    && /tmp/util.sh switch_centos_to_vault_repos \
    && /tmp/util.sh yum_install_clean \
      devtoolset-$DEVTOOLSET_VERSION-gcc \
      devtoolset-$DEVTOOLSET_VERSION-gcc-c++

ARG DEVTOOLSET_ROOT="/opt/rh/devtoolset-$DEVTOOLSET_VERSION/root"
ENV LD_LIBRARY_PATH="$DEVTOOLSET_ROOT/usr/lib64:$DEVTOOLSET_ROOT/usr/lib"
ENV PATH="$DEVTOOLSET_ROOT/usr/bin:$PATH"

RUN /tmp/util.sh yum_install_clean \
      make \
      perl

# zlib
RUN build_dir="/tmp/zlib" && source_dir="$build_dir/_source" && mkdir -p "$build_dir" "$source_dir" \
    && /tmp/util.sh get_github_release 'madler/zlib' | tar xzf - --strip=1 -C "$source_dir" \
    && cd "$build_dir" && "$source_dir/configure" --prefix=/usr/local \
    && make -j && make -j install \
    && rm -rf "$build_dir"

# openssl
RUN build_dir="/tmp/openssl" && source_dir="$build_dir/_source" && mkdir -p "$build_dir" "$source_dir" \
    && curl -sL "https://github.com/openssl/openssl/archive/refs/tags/OpenSSL_1_1_1w.tar.gz" \
      | tar xzf - --strip=1 -C "$source_dir" \
    && cd "$build_dir" && "$source_dir/Configure" linux-$(uname -m) --prefix=/usr --libdir=lib64 shared zlib \
    && make -j && make -j install_sw \
    && rm -rf "$build_dir"

# python
RUN build_dir="/tmp/cpython" && install_dir='/usr/local' && source_dir="$build_dir/_source" \
    && mkdir -p "$build_dir" "$source_dir" \
    && /tmp/util.sh get_github_release 'python/cpython' | tar xzf - --strip=1 -C "$source_dir" \
    && cd "$build_dir" && "$source_dir/configure" \
      --prefix="$install_dir" \
      --disable-test-modules \
      --enable-optimizations \
    && make -j && make altinstall \
    && python_exe="$(ls -1 "$install_dir/bin/python3"* | head -1)" \
    && "$python_exe" -m pip install --upgrade pip \
    && "$python_exe" -m pip install psutil \
    && rm -rf "$build_dir"

# CMake
RUN /tmp/util.sh get_github_release 'Kitware/CMake' "cmake-%v%-linux-$(uname -m).tar.gz" 'v\(3.*\)' \
      | tar xvzf - --strip=1 -C /usr/local

# ninja
RUN build_dir="/tmp/ninja" && source_dir="$build_dir/_source" && mkdir -p "$build_dir" "$source_dir" \
    && /tmp/util.sh get_github_release 'ninja-build/ninja' | tar xzf - --strip=1 -C "$source_dir" \
    && cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=NO -B "$build_dir" -S "$source_dir" \
    && cmake --build "$build_dir" --parallel --target ninja \
    && cp "$build_dir/ninja" /usr/local/bin \
    && rm -rf "$build_dir"

# sccache
RUN /tmp/util.sh get_github_release 'mozilla/sccache' "sccache-v%v%-$(uname -m)-unknown-linux-musl.tar.gz" \
      | tar xvzf - --strip=1 -C /usr/local/bin

RUN /tmp/util.sh yum_install_clean \
      aclocal \
      autoconf \
      automake \
      gettext

# git
RUN build_dir="/tmp/git" && mkdir -p "$build_dir" \
    && /tmp/util.sh get_github_release 'git/git' '' '^v\(2\.49\.[0-9]\+\)$' | tar xzf - --strip=1 -C "$build_dir" \
    && cd "$build_dir" && make configure && ./configure --prefix=/usr && make -j && make -j install \
    && rm -rf "$build_dir"

# ssh is ancient and doesn't support new key format (in case we map .ssh from host)
RUN build_dir="/tmp/ssh" && mkdir -p "$build_dir" \
    && /tmp/util.sh get_github_release 'openssh/openssh-portable' '' '^V_\([0-9]\+_[0-9]\+_P[0-9]\+\)$' \
      | tar xzf - --strip=1 -C "$build_dir" \
    && cd "$build_dir" && autoreconf && ./configure --prefix=/usr && make -j && make -j install \
    && rm -rf "$build_dir"

# libarchive for pacman and fresh bsdtar
RUN build_dir="/tmp/libarchive" && source_dir="$build_dir/_source" && mkdir -p "$build_dir" "$source_dir" \
    && /tmp/util.sh get_github_release 'libarchive/libarchive' | tar xzf - --strip=1 -C "$source_dir" \
    && cd "$build_dir" && cmake -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_LIBDIR=lib64 \
      -DCMAKE_INSTALL_PREFIX='/usr' \
      -DENABLE_TEST=NO \
      -B "$build_dir" -S "$source_dir" \
    && cmake --build "$build_dir" --parallel --target install \
    && rm -rf "$build_dir"

RUN build_dir="/tmp/bash" && mkdir -p "$build_dir" \
    && curl -sL 'https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz' | tar xzf - --strip=1 -C "$build_dir" \
    && cd "$build_dir" && ./configure --prefix=/ && make -j install \
    && rm -rf "$build_dir"

# fakeroot is there
RUN /tmp/util.sh yum_install_clean \
    epel-release

RUN /tmp/util.sh yum_install_clean \
      binutils \
      bison \
      chrpath \
      fakeroot \
      file \
      flex \
      libtool \
      patch \
      pkgconfig \
      sudo \
      texinfo \
      which \
      xz

# install pacman
COPY assets/install-pacman.sh /tmp/install-pacman.sh
RUN /tmp/install-pacman.sh && rm -rf /tmp/build-prerequisites

# set up build user and build dirs
RUN groupadd -r --gid 1001 build \
    && useradd --no-log-init --create-home -g build -r --uid 1001 build \
    && mkdir -p /etc/sudoers.d \
    && echo 'build ALL=(root) NOPASSWD:ALL' >/etc/sudoers.d/build \
    && chmod 0440 /etc/sudoers.d/build \
    && mkdir -p /linux /workdir \
    && chown build:build /linux /workdir

USER build
WORKDIR /workdir
