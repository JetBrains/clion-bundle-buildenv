#!/bin/bash

set -e

package="${1}"

cd $(dirname ${BASH_SOURCE})

pushd "${package}"

DESTDIR="$(pwd)/.makepkg"
export PKGDEST="${DESTDIR}"/pkg
export SRCDEST="${DESTDIR}"/src
export LOGDEST="${DESTDIR}"/log
export BUILDDIR="${DESTDIR}"/build
mkdir -p "${PKGDEST}" "${SRCDEST}" "${LOGDEST}" "${BUILDDIR}"
chmod -R a+w "${DESTDIR}"

set -x

su build -c "/usr/local/bin/makepkg --noconfirm --skippgpcheck --nocheck --nodeps --cleanbuild"
/usr/local/bin/pacman --noconfirm --force -U "${PKGDEST}"/"${package}"-*.pkg.tar.*
rm -rf "${DESTDIR}"

set +x

popd
