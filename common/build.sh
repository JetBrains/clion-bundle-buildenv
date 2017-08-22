#!/bin/bash

# Author: Eldar Abusalimov <Eldar.Abusalimov@jetbrains.com>

# This work is derived from: https://github.com/Alexpux/MINGW-packages
#
# AppVeyor and Drone Continuous Integration for MSYS2
# Author: Renato Silva <br.renatosilva@gmail.com>
# Author: Qian Hong <fracting@gmail.com>

export BUILD_ROOT_DIR="$(dirname $(readlink -e "${0}"))"

source "${BUILD_ROOT_DIR}/libbuild.sh"


if [ "$#" -lt 2 ]; then
    echo "Usage: $0 makepkg.conf package..." >&2
    exit 1
fi

if [ ! -f "${1}" ]; then
    echo "${1}: No such file" >&2
    exit 1
fi
MAKEPKG_CONF=$(readlink -e "${1}"); shift

source "${MAKEPKG_CONF}"

deploy_enabled && [ -d artifacts ] || mkdir -p artifacts

git_config user.name  "${GIT_COMMITTER_NAME}"
git_config user.email "${GIT_COMMITTER_EMAIL}"

export TMPDIR=$(mktemp -d)
set_on_error_trap "rm -rf ${TMPDIR}"

test -z "$@" && failure 'No packages specified'
define_build_order "$@" || failure 'Could not determine build order'


# Build
message 'Building packages' "${packages[@]}"

for package in "${packages[@]}"; do
    export PACMAN=false  # just to be sure makepkg won't call it
    execute 'Building binary' makepkg --noconfirm --skippgpcheck --nocheck --nodeps \
       --cleanbuild --config "${MAKEPKG_CONF}"

    execute 'Installing' tar xvf *.pkg.tar.xz -C / ${PREFIX#/}
    deploy_enabled && mv -f "${package}"/*.pkg.tar.xz artifacts

    if [[ "${package}" == mingw-* ]]; then
        for package_arg in "$@"; do
            if [[ "${package}" == "${package_arg}" ]]; then
                package_runtime_dependencies ${package}
                deploy_enabled && mv "${package}"/*-dll-dependencies.tar.xz artifacts 2>/dev/null || true
            fi
        done
    fi
    unset package
done

success 'All packages built successfully'
