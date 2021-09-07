FROM alpine:edge as gcc

RUN apk update \
 && apk upgrade --no-cache

RUN apk add --no-cache \
     g++ \
     gcc \
     binutils

FROM alpine:edge

COPY --from=gcc /usr /usr/local

RUN apk update \
 && apk upgrade --no-cache

RUN apk add --no-cache \
     bash \
     ccache \
     curl \
     git \
     file \
     fakeroot \
     m4 \
     make \
     mingw-w64-gcc \
     pacman-makepkg \
     patch \
     perl \
     texinfo \
     xz

# some tools/libraries reuquire build system
# compiler, we avoid gnu to 
# RUN apk add --no-cache \
#      clang \
#      compiler-rt \
#      compiler-rt-static \
#      lld \
#      llvm \
#      musl-dev

# RUN apk add --no-cache \
#      gcc \
#      musl-dev

# # some of Development Tools (build-essential)
# RUN yum -y update \
#  && yum -y install \
#       autoconf \
#       automake \
#       binutils \
#       bison \
#       flex \
#       gcc \
#       gcc-c++ \
#       gettext \
#       libtool \
#       make \
#       patch \
#       pkgconfig \
#  && yum -y install \
#       elfutils \
#       file \
#       git \
#  && yum clean all

# RUN yum -y update \
#  && yum -y install \
#       mingw32-gcc \
#       mingw32-gcc-c++ \
#       mingw64-gcc \
#       mingw64-gcc-c++ \
#  && yum clean all

#      #  gmp-devel \
#      #  libmpc-devel \
#      #  mpfr-devel \

# # RUN mkdir /tmp/gcc \
# #  && pushd /tmp/gcc \
# #  && curl -sL 'ftpmirror.gnu.org/gcc/gcc-11.1.0/gcc-11.1.0.tar.gz' \
# #   | tar xzf - --strip=1 \
# #  && ./configure --prefix=/usr --disable-multilib --enable-languages=c,c++ \
# #  && make -j "$(nproc)" \
# #  && make install-strip \
# #  && popd \
# #  && rm -rf /tmp/gcc

# RUN yum -y update \
#  && yum -y install \
#       bsdtar \
#       bzip2 \
#       chrpath \
#       fakeroot \
#       libarchive-devel \
#       openssl \
#       sudo \
#       texinfo \
#       xz \
#  && yum clean all

# # makepkg has /usr/lib/ccache/bin directory hardcoded
# RUN yum -y update \
#  && yum -y install \
#       ccache \
#  && yum clean all \
#  && mkdir -p /usr/lib/ccache \
#  && ln -s /usr/lib64/ccache /usr/lib/ccache/bin

# COPY assets/ /tmp/build-prerequisites
# RUN chmod a+x /tmp/build-prerequisites/*.sh \
#  && /tmp/build-prerequisites/install-pacman.sh \
#  && rm -rf /tmp/build-prerequisites

# RUN mkdir -p /win /workdir \
#  && chown build:build /win /workdir

# RUN yum -y update \
#  && yum -y install \
#       diffutils \
#  && yum clean all

# USER build
# WORKDIR /workdir
