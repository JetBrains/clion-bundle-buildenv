FROM base/devel


RUN pacman --quiet --noconfirm -Sy && pacman --quiet --noconfirm -S \
      mingw-w64 \
      git \
  && rm -f \
      /var/cache/pacman/pkg/* \
      /var/lib/pacman/sync/* \
      /README \
      /etc/pacman.d/mirrorlist.pacnew

RUN (echo ; \
     echo "[multilib]"; \
     echo "Include = /etc/pacman.d/mirrorlist";) >> /etc/pacman.conf \
 && pacman --quiet --noconfirm -Sy && pacman --quiet --noconfirm -S \
      wine

RUN groupadd -r build \
 && useradd --no-log-init -r -m -g build build \
 && echo "build ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/build && \
    chmod 0440 /etc/sudoers.d/build

RUN mkdir -p /opt \
 && chown build:build /opt

WORKDIR /home/build

COPY common/ ./
COPY mingw-w64/ ./

RUN chown -R build:build . \
 && chmod a+x *.sh

USER build
