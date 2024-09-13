FROM dockcross/windows-arm64

RUN groupadd -r --gid 1001 build \
 && useradd --no-log-init --create-home -g build -r --uid 1001 build \
 && mkdir -p /etc/sudoers.d \
 && echo "build ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/build \
 && chmod 0440 /etc/sudoers.d/build

# some of Development Tools (build-essential)
RUN apt-get update \
 && apt-get dist-upgrade -y \
 && apt-get -y install \
      autoconf \
      automake \
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
      elfutils \
      file \
      git \
 && apt-get clean

RUN apt-get -y update \
 && apt-get -y install \
      libarchive-tools \
      bzip2 \
      chrpath \
      fakeroot \
      libarchive-dev \
      openssl \
      sudo \
      texinfo \
      xz-utils \
 && apt-get clean

# /usr/bin/curl: /usr/local/lib/libcurl.so.4: no version information available (required by /usr/bin/curl)
# /usr/bin/curl: symbol lookup error: /usr/bin/curl: undefined symbol: curl_easy_header, version CURL_OPENSSL_4
RUN rm /usr/local/lib/libcurl.so.4

# makepkg has /usr/lib/ccache/bin directory hardcoded
RUN apt-get -y update \
 && apt-get -y install \
      ccache \
 && apt-get clean \
 && mkdir -p /usr/lib/ccache \
 && ln -s /usr/lib64/ccache /usr/lib/ccache/bin

COPY assets/ /tmp/build-prerequisites
RUN chmod a+x /tmp/build-prerequisites/*.sh \
 && CC=gcc CXX=gcc /tmp/build-prerequisites/install-pacman.sh \
 && rm -rf /tmp/build-prerequisites

RUN mkdir -p /win /workdir \
 && chown build:build /win /workdir

USER build
WORKDIR /workdir
