#!/bin/bash

# Author: Eldar Abusalimov <Eldar.Abusalimov@jetbrains.com>

# This work is derived from: https://github.com/Alexpux/MINGW-packages
#
# Continuous Integration Library for MSYS2
# Author: Renato Silva <br.renatosilva@gmail.com>
# Author: Qian Hong <fracting@gmail.com>

# Enable colors
normal=$(tput sgr0)
red=$(tput setaf 1)
green=$(tput setaf 2)
cyan=$(tput setaf 6)

set_on_error_trap() {
    trap "${1}" INT QUIT TERM HUP EXIT
}

# Basic status function
_status() {
    local type="${1}"
    local status="${package:+${package}: }${2}"
    local items=("${@:3}")
    case "${type}" in
        failure) local color="${red}";   title='[BUILD] FAILURE:' ;;
        success) local color="${green}"; title='[BUILD] SUCCESS:' ;;
        message) local color="${cyan}";  title='[BUILD]'
    esac
    printf "%s\n" "${color}${title}${normal} ${status}"
    printf "${items:+\t%s\n}" "${items:+${items[@]}}"
}

# Get package information
_package_info() {
    local package="${1}"
    local properties=("${@:2}")
    for property in "${properties[@]}"; do
        eval "${property}=()"
        test -f "${package}/PKGBUILD" || failure "Unknown package"
        local value=($(
            MINGW_PACKAGE_PREFIX='mingw-w64' source "${package}/PKGBUILD"
            eval echo "\${${property}[@]}"))
        eval "${property}=(\"\${value[@]}\")"
    done
}

# Package provides another
_package_provides() {
    local package="${1}"
    local another="${2}"
    local pkgname provides
    _package_info "${package}" pkgname provides
    for pkg_name in "${pkgname[@]}";  do [[ "${pkg_name}" = "${another}" ]] && return 0; done
    for provided in "${provides[@]}"; do [[ "${provided}" = "${another}" ]] && return 0; done
    return 1
}

# Add package to build after required dependencies
_build_add() {
    local package="${1}"
    local depends makedepends
    for sorted_package in "${sorted_packages[@]}"; do
        [[ "${sorted_package}" = "${package}" ]] && return 0
    done
    message "Resolving dependencies"
    _package_info "${package}" depends makedepends
    for dependency in "${depends[@]}" "${makedepends[@]}"; do
        # for unsorted_package in "${packages[@]}"; do
        #     [[ "${package}" = "${unsorted_package}" ]] && continue
        #     _package_provides "${unsorted_package}" "${dependency}" && _build_add "${unsorted_package}"
        # done
        _build_add "${dependency}"
    done
    sorted_packages+=("${package}")
}

# Git configuration
git_config() {
    local name="${1}"
    local value="${2}"
    test -n "$(git config ${name})" && return 0
    git config --global "${name}" "${value}" && return 0
    failure 'Could not configure Git for makepkg'
}

# Run command with status
execute(){
    local status="${1}"
    local command="${2}"
    local arguments=("${@:3}")
    cd "${package:-.}"
    message "${status}"
    if [[ "${command}" != *:* ]]
        then ${command} ${arguments[@]}
        else ${command%%:*} | ${command#*:} ${arguments[@]}
    fi || failure "${status} failed"
    cd - > /dev/null
}

# Sort packages by dependency
define_build_order() {
    local sorted_packages=()
    for unsorted_package in "$@"; do
        _build_add "${unsorted_package}"
    done
    packages=("${sorted_packages[@]}")
}

# Add packages to repository
create_pacman_repository() {
    local name="${1}"
    # _download_previous "${name}".{db,files}{,.tar.xz}
    repo-add "${name}.db.tar.xz" *.pkg.tar.xz
}

# Deployment is enabled
deploy_enabled() {
    true
}

# Status functions
failure() { local status="${1}"; local items=("${@:2}"); _status failure "${status}." "${items[@]}"; exit 1; }
success() { local status="${1}"; local items=("${@:2}"); _status success "${status}." "${items[@]}"; exit 0; }
message() { local status="${1}"; local items=("${@:2}"); _status message "${status}"  "${items[@]}"; }

# Add runtime dependencies of a binary
_package_dll() {
    local pkgdir=${1}
    local dlldir=${2}
    local prog="${3}"

    [ -f "${prog}" ] && [ -x "${prog}" ] || return 0
    [ ! -e ${dlldir}${MINGW_PREFIX}/bin/$(basename "${prog}") ] || return 0

    # https://stackoverflow.com/a/33174211/545027
    local dll_names=$(${MINGW_CHOST}-strings ${prog} | grep -i '\.dll$')

    message "binary ${prog}" ${dll_names}

    if [ $(readlink -m "${prog}") != $(realpath -m "${pkgdir}${MINGW_PREFIX}/bin/$(basename "$prog")") ]; then
        mkdir -p ${dlldir}${MINGW_PREFIX}/bin/
        cp "${prog}" ${dlldir}${MINGW_PREFIX}/bin/ || failure "Couldn't copy ${prog}"
    fi

    for dll_name in ${dll_names}; do
        for host_dll in /usr/${MINGW_CHOST}/bin/"${dll_name}" \
                            ${MINGW_PREFIX}/bin/"${dll_name}"; do
            if [ -f "${host_dll}" ] && [ -x "${host_dll}" ]; then
                _package_dll ${pkgdir} ${dlldir} "${host_dll}"
            fi
        done
    done
}

package_runtime_dependencies() {
    for package in "$@"; do
        _package_info "${package}" pkgname pkgver pkgrel
        local pkgdir=$(pwd)/${package}/pkg/${MINGW_PACKAGE_PREFIX}-${pkgname#mingw-w64-}
        local dlldir=${TMPDIR}/${package}-dll

        message "Resolving runtime DLL dependencies"
        mkdir -p ${dlldir}

        for prog in ${pkgdir}${MINGW_PREFIX}/bin/*; do
            _package_dll ${pkgdir} ${dlldir} "${prog}"
        done

        tar -Jcf ${package}/${MINGW_PACKAGE_PREFIX}-${pkgname#mingw-w64-}-${pkgver}-${pkgrel}-dll-dependencies.tar.xz -C ${dlldir} . --xform='s:^\./::'
        rm -rf ${dlldir}
    done
}
