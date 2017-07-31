FROM base/devel

RUN pacman --quiet --noconfirm -Sy && pacman --quiet --noconfirm -S \
  git


RUN groupadd -r build \
 && useradd --no-log-init -r -m -g build build \
 && echo "build ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/build && \
    chmod 0440 /etc/sudoers.d/build
