FROM base/devel

RUN groupadd -r --gid 1001 build \
 && useradd --no-log-init --create-home -g build -r --uid 1001 build \
 && mkdir -p /etc/sudoers.d \
 && echo "build ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/build \
 && chmod 0440 /etc/sudoers.d/build

RUN mkdir -p /opt /workdir \
 && chown build:build /opt /workdir

RUN pacman --quiet --noconfirm -Sy && pacman --quiet --noconfirm -S \
      mingw-w64 \
      git \
  && rm -f \
      /var/cache/pacman/pkg/* \
      /var/lib/pacman/sync/* \
      /README \
      /etc/pacman.d/mirrorlist.pacnew

USER build
WORKDIR /workdir
