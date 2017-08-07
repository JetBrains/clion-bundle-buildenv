#!/bin/bash

# AppVeyor and Drone Continuous Integration for MSYS2
# Author: Renato Silva <br.renatosilva@gmail.com>
# Author: Qian Hong <fracting@gmail.com>

# Configure
cd "$(dirname "$0")"
source 'libbuild.sh'
source 'makepkg-mingw64.conf'
deploy_enabled && mkdir -p artifacts
# git_config user.email 'ci@msys2.org'
# git_config user.name  'MSYS2 Continuous Integration'
git config --global user.email 'Eldar.Abusalimov@jetbrains.com'
git config --global user.name  'Eldar Abusalimov'
# git remote add upstream 'https://github.com/Alexpux/MINGW-packages'
# git fetch --quiet upstream

# Detect
# list_commits  || failure 'Could not detect added commits'
# list_packages || failure 'Could not detect changed files'
# message 'Processing changes' "${commits[@]}"
test -z "$@" && failure 'No packages specified'
define_build_order "$@" || failure 'Could not determine build order'

export PACMAN=~/pacman-wrapper
mkdir -p ~/pacman/{db,root,cache}

execute 'Generating pacman repository' repo-add ~/pacman/db/repo.db.tar.xz
execute 'Syncing pacman repository' $PACMAN -Syy

export TMPDIR=$(mktemp -d)
set_on_error_trap "rm -rf ${TMPDIR}"
mkdir -p ${TMPDIR}/${CHOST}-toolchain/bin
for tool in strip readelf objcopy; do
    ln -s $(which ${CHOST}-$tool) ${TMPDIR}/${CHOST}-toolchain/bin/$tool
done
export PATH=${TMPDIR}/${CHOST}-toolchain/bin:"$PATH"

# Build
message 'Building packages' "${packages[@]}"
# execute 'Updating system' update_system
# execute 'Approving recipe quality' check_recipe_quality
for package in "${packages[@]}"; do
    # execute 'Building binary' makepkg-mingw --noconfirm --noprogressbar --skippgpcheck --nocheck --syncdeps --rmdeps --cleanbuild
    execute 'Building binary' makepkg --noconfirm --skippgpcheck --nocheck \
       --syncdeps --rmdeps --cleanbuild --config $(pwd)/makepkg-mingw64.conf
    # execute 'Building source' makepkg --noconfirm --noprogressbar --skippgpcheck --allsource --config ~/makepkg-mingw64.conf
    execute 'Installing' "$PACMAN" --noconfirm --upgrade *.pkg.tar.xz
    deploy_enabled && mv "${package}"/*.pkg.tar.xz artifacts
    # deploy_enabled && mv "${package}"/*.src.tar.gz artifacts
    unset package
done

# Deploy
deploy_enabled && cd artifacts || success 'All packages built successfully'
# execute 'Generating pacman repository' create_pacman_repository "${PACMAN_REPOSITORY_NAME:-repo}"
# execute 'Generating build references'  create_build_references  "${PACMAN_REPOSITORY_NAME:-ci-build}"
# execute 'SHA-256 checksums' sha256sum *
success 'All artifacts built successfully'
