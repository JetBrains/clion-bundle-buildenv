#!/bin/bash

set -ex

cd $(dirname ${BASH_SOURCE})

mkdir pacman-build
pushd pacman-build

curl https://sources.archlinux.org/other/pacman/pacman-5.0.2.tar.gz | tar xz
cd pacman-5.0.2
./configure
make
make install

popd
rm -rf pacman-build
