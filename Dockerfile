FROM base/devel


RUN pacman --quiet --noconfirm -Sy && pacman --quiet --noconfirm -S \
      mingw-w64 \
      git \
  && rm -f \
      /var/cache/pacman/pkg/* \
      /var/lib/pacman/sync/* \
      /README \
      /etc/pacman.d/mirrorlist.pacnew

RUN mkdir -p /opt \
 && chmod a+w /opt

RUN groupadd -r build \
 && useradd --no-log-init -r -m -g build build \
 && echo "build ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/build && \
    chmod 0440 /etc/sudoers.d/build

WORKDIR /home/build

COPY . ./

RUN chown -R build:build . \
 && chmod a+x *.sh

USER build
