FROM centos:6

RUN groupadd -r --gid 1001 build \
 && useradd --no-log-init --create-home -g build -r --uid 1001 build \
 && mkdir -p /etc/sudoers.d \
 && echo "build ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/build \
 && chmod 0440 /etc/sudoers.d/build

RUN mkdir -p /opt /workdir \
 && chown build:build /opt /workdir

RUN (echo ; \
     echo "group_package_types=mandatory";) >> /etc/yum.conf \
 && yum -y update \
 && yum -y groupinstall "Development Tools" \
 && yum -y install \
      sudo \
      git \
 && yum clean all

RUN yum -y update \
 && yum -y install \
      centos-release-scl \
 && yum -y install \
      devtoolset-3-gcc \
      devtoolset-3-gcc-c++ \
 && yum clean all

COPY docker-assets/linux/bsdtar.repo /etc/yum.repos.d/bsdtar.repo
RUN yum -y update --skip-broken \
 && yum -y install \
      bsdtar \
      chrpath \
      fakeroot \
      libarchive \
      libarchive-devel \
      texinfo \
 && yum clean all

COPY docker-assets/linux/build-prerequisites/install-pacman.sh /tmp/build-prerequisites/
RUN chmod a+x /tmp/build-prerequisites/install-pacman.sh \
 && /tmp/build-prerequisites/install-pacman.sh

RUN (echo "#!/bin/bash"; \
     echo "source scl_source enable devtoolset-3";) > /etc/profile.d/scl-enable-devtoolset-3.sh \
 && chmod a+x /etc/profile.d/scl-enable-devtoolset-3.sh

USER build

COPY docker-assets/linux/build-prerequisites/bash/ /tmp/build-prerequisites/bash/
RUN pushd /tmp/build-prerequisites/bash \
 && sudo chmod -R a+w . \
 && /usr/local/bin/makepkg --noconfirm --skippgpcheck --nocheck --nodeps --cleanbuild \
 && sudo /usr/local/bin/pacman --noconfirm --force -U bash-*.pkg.tar.gz \
 && popd

WORKDIR /workdir
ENTRYPOINT ["/bin/bash", "-l"]
