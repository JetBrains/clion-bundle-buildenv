#!/bin/bash

# AppVeyor and Drone Continuous Integration for MSYS2
# Author: Renato Silva <br.renatosilva@gmail.com>
# Author: Qian Hong <fracting@gmail.com>

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 makepkg.conf package..." >&2
    exit 1
fi

if [ ! -f "${1}" ]; then
    echo "${1}: No such file" >&2
    exit 1
fi
MAKEPKG_CONF=$(realpath "${1}"); shift

# Configure
DIR="$(dirname "$0")"
source "${DIR}/libbuild.sh"
source "${MAKEPKG_CONF}"
deploy_enabled && [ -d artifacts ] || mkdir -p artifacts
# git_config user.email 'ci@msys2.org'
# git_config user.name  'MSYS2 Continuous Integration'
# git config --global user.email 'Eldar.Abusalimov@jetbrains.com'
# git config --global user.name  'Eldar Abusalimov'
# git remote add upstream 'https://github.com/Alexpux/MINGW-packages'
# git fetch --quiet upstream

# Detect
# list_commits  || failure 'Could not detect added commits'
# list_packages || failure 'Could not detect changed files'
# message 'Processing changes' "${commits[@]}"
test -z "$@" && failure 'No packages specified'
define_build_order "$@" || failure 'Could not determine build order'

# mkdir -p ~/pacman/{db,root,cache}

# execute 'Generating pacman repository' repo-add ~/pacman/db/repo.db.tar.xz
export PACMAN=false
# execute 'Syncing pacman repository' $PACMAN -Syy

export TMPDIR=$(mktemp -d)
set_on_error_trap "rm -rf ${TMPDIR}"
# mkdir -p ${TMPDIR}/${CHOST}-toolchain/bin
# for tool in strip readelf objcopy; do
#     ln -s $(which ${CHOST}-$tool) ${TMPDIR}/${CHOST}-toolchain/bin/$tool
# done
# export PATH=${TMPDIR}/${CHOST}-toolchain/bin:"$PATH"

# Build
message 'Building packages' "${packages[@]}"
# execute 'Updating system' update_system
# execute 'Approving recipe quality' check_recipe_quality
for package in "${packages[@]}"; do
    # execute 'Building binary' makepkg-mingw --noconfirm --noprogressbar --skippgpcheck --nocheck --syncdeps --rmdeps --cleanbuild
    execute 'Building binary' makepkg --noconfirm --skippgpcheck --nocheck --nodeps \
       --cleanbuild --config "${MAKEPKG_CONF}"
    # execute 'Building source' makepkg --noconfirm --noprogressbar --skippgpcheck --allsource --config ~/makepkg-mingw64.conf
    # execute 'Installing' $PACMAN --noconfirm --upgrade *.pkg.tar.xz
    execute 'Installing' tar xvf *.pkg.tar.xz ${MINGW_PREFIX#/} -C /
    deploy_enabled && mv "${package}"/*.pkg.tar.xz artifacts
    # deploy_enabled && mv "${package}"/*.src.tar.gz artifacts
    for package_arg in "$@"; do
        if [ ${package} == ${package_arg} ]; then
            package_runtime_dependencies ${package}
            deploy_enabled && mv "${package}"/*-dll-dependencies.tar.xz artifacts 2>/dev/null || true
        fi
    done
    unset package
done

# Deploy
deploy_enabled && cd artifacts || success 'All packages built successfully'
# execute 'Generating pacman repository' create_pacman_repository "${PACMAN_REPOSITORY_NAME:-repo}"
# execute 'Generating build references'  create_build_references  "${PACMAN_REPOSITORY_NAME:-ci-build}"
# execute 'SHA-256 checksums' sha256sum *
success 'All artifacts built successfully'
