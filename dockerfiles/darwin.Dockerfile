ARG OSXCROSS_COMMIT="ff8d100f3f026b4ffbe4ce96d8aac4ce06f1278b"
ARG OSXCROSS_DIR="/osxcross"
ARG ALPINE_TAG="3.17"

FROM alpine:$ALPINE_TAG as osxcross

ARG OSXCROSS_DIR OSXCROSS_COMMIT

RUN apk upgrade \
  && apk add --no-cache \
    bash \
    bsd-compat-headers \
    build-base \
    clang \
    cmake \
    file \
    musl-fts-dev \
    gcc \
    git \
    libc-dev \
    libstdc++ \
    libxml2-dev \
    lld \
    llvm-dev \
    llvm-static \
    make \
    musl-dev \
    openssl-dev \
    tar \
    patch \
    python3 \
    xz

RUN mkdir "$OSXCROSS_DIR" \
  && cd "$OSXCROSS_DIR" \
  && git init \
  && git fetch 'https://github.com/tpoechtrager/osxcross.git' $OSXCROSS_COMMIT \
  && git checkout FETCH_HEAD

COPY "MacOSX12.0.sdk.tar.xz" "$OSXCROSS_DIR/tarballs/"

RUN UNATTENDED=1 OSX_VERSION_MIN=10.14 bash "$OSXCROSS_DIR/build.sh"

RUN PATH="$OSXCROSS_DIR/target/bin:$PATH" ENABLE_COMPILER_RT_INSTALL=1 DISABLE_PARALLEL_ARCH_BUILD=1 \
  bash "$OSXCROSS_DIR/build_compiler_rt.sh"


FROM alpine:$ALPINE_TAG

ARG OSXCROSS_DIR

COPY --from=osxcross /osxcross/target /usr/local

COPY --from=osxcross /usr/lib/clang /usr/lib/clang

RUN apk upgrade \
  && apk add --no-cache \
    autoconf \
    automake \
    bash \
    binutils \
    bison \
    ccache \
    clang \
    cmake \
    coreutils \
    curl \
    gcc \
    git \
    fakeroot \
    file \
    flex \
    musl-fts \
    m4 \
    musl-dev \
    libcrypto3 \
    libtool \
    lld \
    llvm \
    make \
    pacman-makepkg \
    patch \
    python3 \
    texinfo \
    xz

RUN mkdir -p /darwin /workdir \
  && chmod 777 /darwin /workdir
