# Centos-based image with makepkg, ccache and devtoolset-11
# for building PKGBUILD packages.

FROM centos:7

RUN groupadd -r --gid 1001 build \
 && useradd --no-log-init --create-home -g build -r --uid 1001 build \
 && mkdir -p /etc/sudoers.d \
 && echo "build ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/build \
 && chmod 0440 /etc/sudoers.d/build

# some of Development Tools (build-essential)
RUN yum -y update \
 && yum -y install \
      epel-release \
 && yum -y install \
      autoconf \
      automake \
      binutils \
      bison \
      flex \
      gcc \
      gcc-c++ \
      gettext \
      libtool \
      make \
      patch \
      pkgconfig \
 && yum -y install \
      elfutils \
      file \
      git \
 && yum clean all

RUN yum -y update \
 && yum -y install \
      centos-release-scl-rh \
 && yum -y --enablerepo=centos-sclo-rh-testing install \
      devtoolset-10-gcc \
      devtoolset-10-gcc-c++ \
 && yum clean all

RUN yum -y update \
 && yum -y install \
      bzip2 \
      chrpath \
      fakeroot \
      libarchive-devel \
      openssl \
      sudo \
      texinfo \
      xz \
 && yum clean all

RUN yum -y update \
 && yum -y install \
      bsdtar \
 && yum clean all

RUN curl -fsSL "https://github.com/Kitware/CMake/releases/download/v3.24.3/cmake-3.24.3-linux-aarch64.tar.gz" \
 | tar xvzf - --strip=1 -C /usr/local

ENV PATH="/opt/rh/devtoolset-10/root/usr/bin:${PATH}"

# makepkg has /usr/lib/ccache/bin directory hardcoded
RUN yum -y update \
 && yum -y install \
      ccache \
 && yum clean all \
 && mkdir -p /usr/lib/ccache \
 && ln -s /usr/lib64/ccache /usr/lib/ccache/bin

# makepkg requires newer version of git
RUN yum -y update \
 && yum -y install \
      openssl-devel \
      curl-devel \
      expat-devel \
 && yum clean all \
 && mkdir /tmp/git \
 && pushd /tmp/git \
 && curl -sL "https://github.com/git/git/archive/v2.24.1.tar.gz" \
  | tar xzf - --strip=1 \
 && make prefix=/usr install \
 && popd \
 && rm -rf /tmp/git

# ssh is ancient and doesn't support new key
# format (in case we map .ssh from host)
RUN mkdir /tmp/ssh \
 && pushd /tmp/ssh \
 && curl -sL "https://github.com/openssh/openssh-portable/archive/V_8_1_P1.tar.gz" \
  | tar xzf - --strip=1 \
 && autoreconf \
 && ./configure --prefix=/usr \
 && make install \
 && popd \
 && rm -rf /tmp/ssh

COPY assets/ /tmp/build-prerequisites
RUN chmod a+x /tmp/build-prerequisites/*.sh \
 && /tmp/build-prerequisites/install-pacman.sh \
 && rm -rf /tmp/build-prerequisites

RUN mkdir -p /linux /workdir \
 && chown build:build /linux /workdir

USER build
WORKDIR /workdir
