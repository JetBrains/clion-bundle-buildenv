#!/bin/bash

# Author: Eldar Abusalimov <Eldar.Abusalimov@jetbrains.com>

# This work is derived from: https://github.com/Alexpux/MINGW-packages
#
# AppVeyor and Drone Continuous Integration for MSYS2
# Author: Renato Silva <br.renatosilva@gmail.com>
# Author: Qian Hong <fracting@gmail.com>

prog_version=0.2

export BUILD_ROOT_DIR="$(pwd)"


if [[ -n "${TERM}" ]]; then
    # Enable colors
    normal=$(tput sgr0)
    red=$(tput setaf 1)
    green=$(tput setaf 2)
    cyan=$(tput setaf 6)
else
    normal=""
    red=""
    green=""
    cyan=""
fi

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
    printf "%s\n" "${color}${title}${normal} ${status}" >&2
    printf "${items:+\t%s\n}" "${items:+${items[@]}}" >&2
}

# Status functions
failure() { local status="${1}"; local items=("${@:2}"); _status failure "${status}." "${items[@]}"; exit 1; }
success() { local status="${1}"; local items=("${@:2}"); _status success "${status}." "${items[@]}"; exit 0; }
message() { local status="${1}"; local items=("${@:2}"); _status message "${status}"  "${items[@]}"; }


# Git configuration
git_config() {
    local name="${1}"
    local value="${2}"
    test -n "$(git config ${name})" && return 0
    git config --global "${name}" "${value}" && return 0
    failure 'Could not configure Git for makepkg'
}


# Get package information
_package_info() {
    local package="${1}"
    local properties=("${@:2}")
    test -f "${BUILD_ROOT_DIR}/${package}/PKGBUILD" || failure "Unknown package"
    for property in "${properties[@]}"; do
        eval "${property}=()"
        local value=($(
            source "${MAKEPKG_CONF}"
            source "${BUILD_ROOT_DIR}/${package}/PKGBUILD"
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

# Sort packages by dependency
define_build_order() {
    local sorted_packages=()
    for unsorted_package in "$@"; do
        _build_add "${unsorted_package}"
    done
    packages=("${sorted_packages[@]}")
}


get_pkgfile() {
    local pkgfile_noext
    pkgfile_noext=$(get_pkgfile_noext "${1}") || failure "Unknown package"
    printf "%s%s\n" "${pkgfile_noext}" "${PKGEXT}"
}

get_pkgfile_noext() {
    epoch=0
    _package_info "${1}" pkgname epoch pkgver pkgrel arch

    if [[ $arch != "any" ]]; then
        arch="$CARCH"
    fi

    if (( epoch > 0 )); then
        printf "%s\n" "${pkgname}-$epoch:$pkgver-$pkgrel-$arch"
    else
        printf "%s\n" "${pkgname}-$pkgver-$pkgrel-$arch"
    fi
}


# Run command with status
execute(){
    local status="${1}"
    local command="${2}"
    local arguments=("${@:3}")
    message "${status}"
    ${command} ${arguments[@]} || failure "${status} failed"
}

execute_cd(){
    local d="${1}"
    local status="${2}"
    local command="${3}"
    local arguments=("${@:4}")
    pushd "${d}" > /dev/null
    message "${status}"
    ${command} ${arguments[@]} || failure "${status} failed"
    popd > /dev/null
}

# Add runtime dependencies of a binary
_package_dll() {
    local pkgdir=${1}
    local dlldir=${2}
    local prog="${3}"

    [ -f "${prog}" ] && [ -x "${prog}" ] || return 0
    [ ! -e ${dlldir}${PREFIX}/bin/$(basename "${prog}") ] || return 0

    # https://stackoverflow.com/a/33174211/545027
    local dll_names=$(${CHOST}-strings ${prog} | grep -i '\.dll$')

    message "binary ${prog}" ${dll_names}

    if [ $(readlink -m "${prog}") != $(realpath -m "${pkgdir}${PREFIX}/bin/$(basename "$prog")") ]; then
        mkdir -p ${dlldir}${PREFIX}/bin/
        cp "${prog}" ${dlldir}${PREFIX}/bin/ || failure "Couldn't copy ${prog}"
    fi

    for dll_name in ${dll_names}; do
        for host_dll in /usr/${CHOST}/bin/"${dll_name}" \
                            ${PREFIX}/bin/"${dll_name}"; do
            if [ -f "${host_dll}" ] && [ -x "${host_dll}" ]; then
                _package_dll ${pkgdir} ${dlldir} "${host_dll}"
            fi
        done
    done
}

package_runtime_dependencies() {
    for package in "$@"; do
        _package_info "${package}" pkgname
        local pkgfile_noext=$(get_pkgfile_noext "${package}")
        local pkgdir=$(pwd)/${package}/pkg/${pkgname}
        local dlldir=${TMPDIR}/${package}-dll

        message "Resolving runtime DLL dependencies"
        mkdir -p ${dlldir}

        for prog in ${pkgdir}${PREFIX}/bin/*; do
            _package_dll ${pkgdir} ${dlldir} "${prog}"
        done

        tar -Jcf "${package}/${pkgfile_noext}-dll-dependencies.tar.xz" -C ${dlldir} . --xform='s:^\./::'
        rm -rf ${dlldir}
    done
}


usage() {
    printf "%s %s\n" "$0" "$prog_version"
    echo
    printf -- "Build packages using makepkg and bundle a single archive\n"
    echo
    printf -- "Usage: %s -c <makepkg.conf> [--] [package...]\n" "$0"
    echo
    printf -- "Options:\n"
    printf -- "  -c, --config <file>  Use an alternate config file (instead of '%s')\n" "$confdir/makepkg.conf"
    printf -- "  --nomakepkg          Do not rebuild packages\n"
    printf -- "  --nobundle           Do not create %s from package files\n" "\$artifactsdir/bundle-\$chost.tar.xz"
    printf -- "  --nodeps             Do not build or bunble dependencies\n"
    printf -- "  -h, --help           Show this help message and exit\n"
    printf -- "  -V, --version        Show version information and exit\n"
    echo
    printf -- "These options can be passed to %s:\n" "makepkg"
    echo
    printf -- "  --clean              Clean up work files after build\n"
    printf -- "  --cleanbuild         Remove %s dir before building the package\n" "\$package/\$srcdir/"
    printf -- "  -g, --geninteg       Generate integrity checks for source files\n"
    printf -- "  -o, --nobuild        Download and extract files only\n"
    printf -- "  -e, --noextract      Do not extract source files (use existing %s dir)\n" "\$package/\$srcdir/"
    printf -- "  -L, --log            Log package build process\n"
    printf -- "  --nocolor            Disable colorized output messages\n"
    echo
}

version() {
    printf "%s %s\n" "$0" "$prog_version"
    makepkg --version
}

MAKEPKG_OPTS=(--force --noconfirm --skippgpcheck --nocheck --nodeps)

NOMAKEPKG=0
NOBUNDLE=0
NODEPS=0
NODEPLOY=0

target_packages=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        # Makepkg Options
        -c|--config)      shift; MAKEPKG_CONF="$1"; MAKEPKG_OPTS+=(--config "${MAKEPKG_CONF}") ;;
        -c=*|--config=*)  MAKEPKG_CONF="${1#*=}";   MAKEPKG_OPTS+=(--config "${MAKEPKG_CONF}") ;;

        --clean)          MAKEPKG_OPTS+=($1) ;;
        --cleanbuild)     MAKEPKG_OPTS+=($1) ;;
        -g|--geninteg)    MAKEPKG_OPTS+=($1); NOBUNDLE=1; NODEPLOY=1 ;;
        -o|--nobuild)     MAKEPKG_OPTS+=($1); NOBUNDLE=1 ;;
        -e|--noextract)   MAKEPKG_OPTS+=($1) ;;
        -L|--log)         MAKEPKG_OPTS+=($1) ;;
        --nocolor)        MAKEPKG_OPTS+=($1) ;;

        --nomakepkg)      NOMAKEPKG=1 ;;
        --nobundle)       NOBUNDLE=1 ;;
        --nodeps)         NODEPS=1 ;;

        -h|--help)        usage; exit 0 ;; # E_OK
        -V|--version)     version; exit 0 ;; # E_OK

        --)               OPT_IND=0; shift; break 2;;
        -*)               echo "${1}: Unknown option\n" >&2
                          usage; exit 1 ;;
        *)                target_packages+=("$1") ;;
    esac
    shift
done

target_packages+=("$@")

if [ ! -n "${MAKEPKG_CONF}" ]; then
    echo "Missing required option: -c <makepkg.conf>" >&2
    usage
    exit 1
fi

if [ ! -f "${MAKEPKG_CONF}" ]; then
    failure "${MAKEPKG_CONF}: File not found"
fi
export MAKEPKG_CONF=$(readlink -e "${MAKEPKG_CONF}"); shift

source "${MAKEPKG_CONF}"

if [ ! -n "${PREFIX}" ]; then
    echo 'Missing $PREFIX variable definition in '"${MAKEPKG_CONF}" >&2
    exit 1
fi
export PATH="$PATH:$PREFIX/bin"

ARTIFACTS_DIR="$(readlink -m "artifacts")"
(( ! NODEPLOY )) && [ -d "${ARTIFACTS_DIR}" ] || mkdir -p "${ARTIFACTS_DIR}"

git_config user.name  "${GIT_COMMITTER_NAME}"
git_config user.email "${GIT_COMMITTER_EMAIL}"

export TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" INT QUIT TERM HUP EXIT


test -z "${target_packages[@]}" && failure 'No packages specified'
if (( ! NODEPS )); then
    define_build_order "${target_packages[@]}" || failure 'Could not determine build order'
else
    packages=("${target_packages[@]}")
fi

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

if (( ! NOMAKEPKG )); then
    # Build
    message 'Building packages' "${packages[@]}"

    for package in "${packages[@]}"; do
        export PACMAN=false  # just to be sure makepkg won't call it
        execute_cd "${package}" 'Building binary' makepkg "${MAKEPKG_OPTS[@]}" --config "${MAKEPKG_CONF}"

        if (( ! NODEPLOY )); then
            [[ -f "${package}"/*-debug-*${PKGEXT} ]] \
               && mv -f "${package}"/*-debug-*${PKGEXT} "${ARTIFACTS_DIR}"
            execute_cd "${package}" 'Installing' tar xvf $(get_pkgfile "${package}") -C / ${PREFIX#/}
            mv -f "${package}"/$(get_pkgfile "${package}") "${ARTIFACTS_DIR}"
        fi
        unset package
    done


    if (( ! NODEPLOY )); then
        if [[ "${CHOST}" == *-w64-mingw* ]]; then
            for package in "${target_packages[@]}"; do
                package_runtime_dependencies ${package}
                mv -f "${package}"/*-dll-dependencies.tar.xz "${ARTIFACTS_DIR}" 2>/dev/null || true
                unset package
            done
        fi
    fi
fi

shopt -s extglob

if (( ! NOBUNDLE )); then
    message "Bundling packages" "${target_packages[@]}"

    BUNDLE_DIR="${ARTIFACTS_DIR}/bundle-${CHOST}"
    rm -rf "${BUNDLE_DIR}"
    mkdir -p "${BUNDLE_DIR}"

    pushd "${BUNDLE_DIR}"

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

    message 'Removing shared library symlinks...'
    while read -rd '' l; do
        rm -vf "$l"
    done < <(find -L .${PREFIX}/lib ! -type d -xtype l -print0)

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
fi

success 'All packages built successfully'
