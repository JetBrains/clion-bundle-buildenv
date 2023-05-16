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

RUN apk add --no-cache \
     autoconf \
     automake \
     gettext \
     gettext-dev \
     gperf \
     libtool \
     pkgconf

RUN mkdir -p /win \
 && chmod 777 /win
