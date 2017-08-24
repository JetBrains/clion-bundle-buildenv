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
export MAKEPKG_CONF=$(readlink -e "${1}"); shift

source "${MAKEPKG_CONF}"

ARTIFACTS_DIR="$(readlink -m "artifacts")"
deploy_enabled && [ -d "${ARTIFACTS_DIR}" ] || mkdir -p "${ARTIFACTS_DIR}"

git_config user.name  "${GIT_COMMITTER_NAME}"
git_config user.email "${GIT_COMMITTER_EMAIL}"

export TMPDIR=$(mktemp -d)
set_on_error_trap "rm -rf ${TMPDIR}"


target_packages=("$@")

test -z "${target_packages[@]}" && failure 'No packages specified'
define_build_order "${target_packages[@]}" || failure 'Could not determine build order'


is_target_package() {
    local target_package
    for target_package in "${target_packages[@]}"; do
        if [[ "${1}" == "${target_package}" ]]; then
            return 0  # true
        fi
    done
    return 1  # false
}

dependency_packages=()
for package in "${packages[@]}"; do
    is_target_package "${package}" || dependency_packages+=("${package}")
    unset package
done


# Build
message 'Building packages' "${packages[@]}"

for package in "${packages[@]}"; do
    export PACMAN=false  # just to be sure makepkg won't call it
    execute_cd "${package}" 'Building binary' makepkg --noconfirm --skippgpcheck --nocheck --nodeps \
       --cleanbuild --config "${MAKEPKG_CONF}"

    deploy_enabled && [[ -f "${package}"/*-debug-*${PKGEXT} ]] \
                   && mv -f "${package}"/*-debug-*${PKGEXT} "${ARTIFACTS_DIR}"
    execute_cd "${package}" 'Installing' tar xvf $(get_pkgfile "${package}") -C / ${PREFIX#/}
    deploy_enabled && mv -f "${package}"/$(get_pkgfile "${package}") "${ARTIFACTS_DIR}"
    unset package
done


if [[ "${CHOST}" == *-w64-mingw* ]]; then
    for package in "${target_packages[@]}"; do
        package_runtime_dependencies ${package}
        deploy_enabled && mv -f "${package}"/*-dll-dependencies.tar.xz "${ARTIFACTS_DIR}" 2>/dev/null || true
        unset package
    done
fi


shopt -s extglob

BUNDLE_DIR="${ARTIFACTS_DIR}/bundle-${CHOST}"
rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}"

pushd "${BUNDLE_DIR}"

message "Bundling packages" "${target_packages[@]}"
if [[ -n ${dependency_packages[*]} ]]; then
    message "... with dependencies" "${dependency_packages[@]}"

    for package in "${dependency_packages[@]}"; do
        execute "Extracting (dependency)" tar xf "${ARTIFACTS_DIR}"/$(get_pkgfile "${package}") ${PREFIX#/}
        unset package
    done
    execute 'Removing dependency binaries...' rm -rvf .${PREFIX}/bin/!(*.dll)
fi

for package in "${target_packages[@]}"; do
    execute "Extracting" tar xf "${ARTIFACTS_DIR}"/$(get_pkgfile "${package}") ${PREFIX#/}
    if [[ "${CHOST}" == *-w64-mingw* ]] \
                                && [[ -f "${ARTIFACTS_DIR}"/$(get_pkgfile_noext "${package}")-dll-dependencies.tar.xz ]]; then
        execute "Extracting DLLs" tar xf "${ARTIFACTS_DIR}"/$(get_pkgfile_noext "${package}")-dll-dependencies.tar.xz ${PREFIX#/}
    fi
    unset package
done

message 'Removing leftover development files...'
while read -rd '' l; do
    rm -vf "$l"
done < <(find . ! -type d -name "*.a" -print0)

while read -rd '' l; do
    rm -vf "$l"
done < <(find . ! -type d -name "*.la" -print0)

rm -rvf .${PREFIX}/lib/pkgconfig
rm -rvf .${PREFIX}/include

# Remove empty directories
find . -depth -type d -exec rmdir '{}' \; 2>/dev/null

execute "Archiving ${BUNDLE_DIR%%/}.tar.xz" tar -Jcf "${BUNDLE_DIR%%/}".tar.xz . --xform='s:^\./::'

popd

success 'All packages built successfully'
