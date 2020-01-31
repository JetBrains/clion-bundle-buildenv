# Centos-based image with makepkg, ccache and devtoolset-7
# for building PKGBUILD packages.

FROM centos:6

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
      centos-release-scl \
 && yum -y install \
      devtoolset-7-gcc \
      devtoolset-7-gcc-c++ \
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
      bsdtar3 \
 && yum clean all \
 && ln -s "$(command -v bsdtar3)" /usr/local/bin/bsdtar

RUN yum -y update \
 && yum -y install \
      cmake3 \
 && yum clean all \
 && ln -s "$(command -v cmake3)" /usr/local/bin/cmake

ENV PATH="/opt/rh/devtoolset-7/root/usr/bin:${PATH}"

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
