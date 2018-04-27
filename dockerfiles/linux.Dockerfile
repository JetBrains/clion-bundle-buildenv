# Centos-based image with pacman, pkgbuild, ccache for building PKGBUILD packages.

FROM centos:6

RUN groupadd -r --gid 1001 build \
 && useradd --no-log-init --create-home -g build -r --uid 1001 build \
 && mkdir -p /etc/sudoers.d \
 && echo "build ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/build \
 && chmod 0440 /etc/sudoers.d/build

RUN yum -y update \
 && yum -y install \
      centos-release-scl \
 && yum -y install \
      devtoolset-7-gcc \
      devtoolset-7-gcc-c++ \
 && yum clean all

RUN yum -y update \
 && yum -y install \
      epel-release \
 && yum -y install \
      chrpath \
      fakeroot \
      git \
      libarchive \
      libarchive-devel \
      m4 \
      patch \
      sudo \
      texinfo \
      xz \
 && yum clean all

RUN yum -y update \
 && yum -y install \
      bsdtar3 \
 && yum clean all \
 && ln -s bsdtar3 "$(dirname $(which bsdtar3))"/bsdtar

RUN yum -y update \
 && yum -y install \
      ccache \
 && yum clean all \
 && mkdir -p /usr/lib/ccache/bin/ \
 && for _prog in "/opt/rh/devtoolset-7/root/usr/bin/" \
        {$(gcc -dumpmachine)-,}{gcc,gcc-[0-9],g++,cc,c++,clang,clang++}; do \
      if [ -f "${_prog}" ]; then ln -s "$(which ccache)" /usr/lib/ccache/bin/"$(basename ${_prog})"; fi; \
    done

ENV PATH="/opt/rh/devtoolset-7/root/usr/bin:${PATH}"

COPY assets/ /tmp/build-prerequisites
RUN chmod a+x /tmp/build-prerequisites/*.sh \
 && /tmp/build-prerequisites/install-pacman.sh \
 && rm -rf /tmp/build-prerequisites

RUN mkdir -p /linux /workdir \
 && chown build:build /linux /workdir

USER build
WORKDIR /workdir
