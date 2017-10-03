#!/bin/bash

# Author: Eldar Abusalimov <Eldar.Abusalimov@jetbrains.com>

# This work is derived from: https://github.com/Alexpux/MINGW-packages
#
# AppVeyor and Drone Continuous Integration for MSYS2
# Author: Renato Silva <br.renatosilva@gmail.com>
# Author: Qian Hong <fracting@gmail.com>

prog_version=0.2


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

    if [[ -n ${TEAMCITY_VERSION} ]]; then
        case "${type}" in
            progress_start)  local teamcity_report="progressStart '${status}'" ;;
            progress_finish) local teamcity_report="progressFinish '${status}'" ;;
            message)         local teamcity_report="progressMessage '${status}'" ;;
            failure)         local teamcity_report="buildProblem description='${status}'" ;;
            success)         local teamcity_report="buildStatus status='SUCCESS' text='${status}'" ;;
        esac
        echo "##teamcity[${teamcity_report}]"
    else
        case "${type}" in
            progress_finish) return 0 ;;  # don't report when running from terminal
            progress_start|message)
                     local color="${cyan}";  title='[BUILD]' ;;
            failure) local color="${red}";   title='[BUILD] FAILURE:' ;;
            success) local color="${green}"; title='[BUILD] SUCCESS:' ;;
        esac
        echo "${color}${title}${normal} ${status}" >&2
    fi

    printf "${items:+\t%s\n}" "${items:+${items[@]}}" >&2
}

# Status functions
failure() { local status="${1}"; local items=("${@:2}"); _status failure "${status}." "${items[@]}"; exit 1; }
success() { local status="${1}"; local items=("${@:2}"); _status success "${status}." "${items[@]}"; exit 0; }
message() { local status="${1}"; local items=("${@:2}"); _status message "${status}"  "${items[@]}"; }
progress_start()  { local status="${1}"; local items=("${@:2}"); _status progress_start  "${status}"  "${items[@]}"; }
progress_finish() { local status="${1}"; local items=("${@:2}"); _status progress_finish "${status}"  "${items[@]}"; }


# Git configuration
git_config() {
    local name="${1}"
    local value="${2}"
    test -n "$(git config ${name})" && return 0
    git config --global "${name}" "${value}" && return 0
    failure 'Could not configure Git for makepkg'
}


# Passes arguments to `find` and removes found files verbosely
find_and_rm() {
    local f
    while read -rd '' f; do
        rm -vf "$f"
    done < <(find "$@" -print0)
}


# Get package information
_package_info() {
    local package="${1}"
    local properties=("${@:2}")
    test -f "${PKG_ROOT_DIR}/${package}/PKGBUILD" || failure "Unknown package"
    for property in "${properties[@]}"; do
        eval "${property}=()"
        local value=($(
            source "${MAKEPKG_CONF}"
            source "${PKG_ROOT_DIR}/${package}/PKGBUILD"
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

pkgfilename() {
    [[ -n "${package}" ]] || failure "\${package} undefined"
    get_pkgfile "${package}"
}


execute_in_pkg() {
    execute_cd "${PKG_ROOT_DIR}/${package}" "$@"
}

# Run command with status
execute(){
    local status="${1}"
    local command="${2}"
    local arguments=("${@:3}")
    progress_start "${status}"
    ${command} ${arguments[@]} || failure "${status} failed"
    progress_finish "${status}"
}

execute_cd(){
    local d="${1}"
    local status="${2}"
    local command="${3}"
    local arguments=("${@:4}")
    progress_start "${status}"
    pushd "${d}" > /dev/null
    ${command} ${arguments[@]} || failure "${status} failed"
    popd > /dev/null
    progress_finish "${status}"
}


# Add runtime dependencies of a binary to ./${PREFIX}/bin/
bundle_dll_dependencies() {
    local binary="${1}"
    local depchain=("${@:2}")

    [[ -f "${binary}" && -x "${binary}" ]] || return 0

    # don't copy at the outermost recursion level, i.e. the executable itself
    if [[ -n ${depchain[*]} ]]; then
        if [[ -e ${PREFIX#/}/bin/$(basename "${binary}") ]]; then  # done already
            return 0
        fi
        message "${binary}: installing as dependency of:" "${depchain[@]}"
        cp "${binary}" ${PREFIX#/}/bin/ || failure "Couldn't copy ${binary}"
    fi

    # https://stackoverflow.com/a/33174211/545027
    local dll_names=($(${CHOST}-strings ${binary} | grep -i '\.dll$'))
    message "${binary}: DLL dependencies:" "${dll_names[@]}"

    for dll_name in "${dll_names[@]}"; do
        local host_dll=/usr/${CHOST}/bin/"${dll_name}"
        if [[ -f "${host_dll}" && -x "${host_dll}" ]]; then  # recurse
            bundle_dll_dependencies "${host_dll}" "${binary}" "${depchain[@]}"
        fi
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
    printf -- "  -P, --pkgroot <dir>  Directory to search packages in (instead of '%s')\n" "\$CWD"
    printf -- "  -c, --config <file>  Use an alternate config file (instead of '%s')\n" "\$pkgroot/makepkg.conf"
    printf -- "  --nomakepkg          Do not rebuild packages\n"
    printf -- "  --nobundle           Do not create '%s' from package files\n" "\$DESTDIR/bundle.tar.xz"
    printf -- "  --nodeps             Do not build or bunble dependencies\n"
    printf -- "  -h, --help           Show this help message and exit\n"
    printf -- "  -V, --version        Show version information and exit\n"
    echo
    printf -- "These options can be passed to %s:\n" "makepkg"
    echo
    printf -- "  --clean              Clean up work files after build\n"
    printf -- "  --cleanbuild         Remove %s dir before building the package\n" "\$package/\$srcdir/"
    printf -- "  -g, --geninteg       Generate integrity checks for source files (implies --nobundle)\n"
    printf -- "  -o, --nobuild        Download and extract files only (implies --nobundle)\n"
    printf -- "  -e, --noextract      Do not extract source files (use existing %s dir)\n" "\$package/\$srcdir/"
    printf -- "  -L, --log            Log package build process\n"
    printf -- "  --nocolor            Disable colorized output messages\n"
    echo
    printf -- "The following variables can be passed through environment:\n"
    echo
    printf -- "  DESTDIR              where to put the resulting bundle  [ \$CWD/artifacts-\$chost ]\n"
    printf -- "  PKGDEST              where all packages will be placed  [ \$DESTDIR/makepkg/pkg ]\n"
    printf -- "  SRCDEST              where source files will be cached  [ \$DESTDIR/makepkg/src ]\n"
    printf -- "  LOGDEST              where all log files will be placed [ \$DESTDIR/makepkg/log ]\n"
    printf -- "  BUILDDIR             where to run package compilation   [ \$DESTDIR/makepkg/build ]\n"
    echo
}

version() {
    printf "%s %s\n" "$0" "$prog_version"
    makepkg --version
}

MAKEPKG_OPTS=(--force --noconfirm --skippgpcheck --nocheck --nodeps)

MAKEPKG_CONF=
PKG_ROOT_DIR=

NOMAKEPKG=0
NOBUNDLE=0
NODEPS=0
NOINSTALL=0
LOGGING=0

target_packages=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -P|--pkgroot)     shift; PKG_ROOT_DIR="$1" ;;
        -P=*|--pkgroot=*) PKG_ROOT_DIR="${1#*=}" ;;

        -c|--config)      shift; MAKEPKG_CONF="$1"; MAKEPKG_OPTS+=(--config "${MAKEPKG_CONF}") ;;
        -c=*|--config=*)  MAKEPKG_CONF="${1#*=}";   MAKEPKG_OPTS+=(--config "${MAKEPKG_CONF}") ;;

        # Makepkg Options
        --clean)          MAKEPKG_OPTS+=($1) ;;
        --cleanbuild)     MAKEPKG_OPTS+=($1) ;;
        -g|--geninteg)    MAKEPKG_OPTS+=($1); NOBUNDLE=1; NOINSTALL=1 ;;
        -o|--nobuild)     MAKEPKG_OPTS+=($1); NOBUNDLE=1 ;;
        -e|--noextract)   MAKEPKG_OPTS+=($1) ;;
        -L|--log)         MAKEPKG_OPTS+=($1); LOGGING=1 ;;
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
for package in "${target_packages[@]}"; do
    _package_info "${package}"  # check package exists
done


PKG_ROOT_DIR="${PKG_ROOT_DIR:-$(pwd)}"
if [ ! -d "${PKG_ROOT_DIR}" ]; then
    failure "${PKG_ROOT_DIR}: Direcrory doesn't exist"
fi
export PKG_ROOT_DIR=$(readlink -e "${PKG_ROOT_DIR}")

MAKEPKG_CONF="${MAKEPKG_CONF:-${PKG_ROOT_DIR}/makepkg.conf}"
if [ ! -f "${MAKEPKG_CONF}" ]; then
    failure "${MAKEPKG_CONF}: File not found"
fi
export MAKEPKG_CONF=$(readlink -e "${MAKEPKG_CONF}")


source "${MAKEPKG_CONF}"


[[ -n ${CHOST} ]] || CHOST=$(gcc -dumpmachine)
[[ "${CHOST}" == *-w64-mingw* ]] && ISMINGW=1 || ISMINGW=0

if [ ! -n "${PREFIX}" ]; then
    failure "${MAKEPKG_CONF}: Missing \$PREFIX variable definition"
fi
export PATH="$PATH:$PREFIX/bin"

# makepkg environmental variables
export DESTDIR=${DESTDIR:-$(pwd)/artifacts-${CHOST}}
export PKGDEST=${PKGDEST:-${DESTDIR}/makepkg/pkg}      #-- Destination: where all packages will be placed
export SRCDEST=${SRCDEST:-${DESTDIR}/makepkg/src}      #-- Source cache: where source files will be cached
export LOGDEST=${LOGDEST:-${DESTDIR}/makepkg/log}      #-- Log files: where all log files will be placed
export BUILDDIR=${BUILDDIR:-${DESTDIR}/makepkg/build}  #-- Build tmp: where makepkg runs package build


test -z "${target_packages[@]}" && failure 'No packages specified'
if (( ! NODEPS )); then
    define_build_order "${target_packages[@]}" || failure 'Could not determine build order'
else
    packages=("${target_packages[@]}")
fi

mkdir -p "${DESTDIR}" "${PKGDEST}" "${SRCDEST}"
(( LOGGING )) && mkdir -p "${LOGDEST}"

git_config user.name  "${GIT_COMMITTER_NAME}"
git_config user.email "${GIT_COMMITTER_EMAIL}"

export TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" INT QUIT TERM HUP EXIT


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

    export PACMAN=false  # just to be sure makepkg won't call it

    for package in "${packages[@]}"; do
        execute_in_pkg 'Building binary' \
            makepkg "${MAKEPKG_OPTS[@]}" --config "${MAKEPKG_CONF}"

        if (( ! NOINSTALL )); then
            execute "Installing to ${PREFIX}" \
                bsdtar -xvf "${PKGDEST}/$(pkgfilename)" -C / ${PREFIX#/}
        fi

        unset package
    done
fi


if (( ! NOBUNDLE )); then
    BUNDLE_DIR="${DESTDIR}/bundle"
    rm -rf "${BUNDLE_DIR}"
    mkdir -p "${BUNDLE_DIR}"

    echo -n "pushd: "; pushd "${BUNDLE_DIR}"

    message "Bundling packages" "${target_packages[@]}"

    if [[ -n ${dependency_packages[*]} ]]; then
        message "... with dependencies" "${dependency_packages[@]}"

        for package in "${dependency_packages[@]}"; do
            execute "Extracting (dependency)" \
                bsdtar -xf "${PKGDEST}/$(pkgfilename)" ${PREFIX#/}
            unset package
        done
        message 'Removing dependency binaries...'
        find_and_rm -L ${PREFIX#/}/bin -xtype l

        while read -rd '' binary ; do
            case "$(file -bi "$binary")" in
                *text/x-shellscript*) ;;
                *)
                     if (( ISMINGW )) && [[ "$binary" != *.exe ]]; then
                         continue
                     fi
                     ;;
            esac
            rm -vf "$binary"
            unset binary
        done < <(find ${PREFIX#/}/bin ! -type d -print0)

    fi

    for package in "${target_packages[@]}"; do
        execute "Extracting" \
            bsdtar -xf "${PKGDEST}/$(pkgfilename)" ${PREFIX#/}
        unset package
    done

    if (( ISMINGW )); then
        binaries=(${PREFIX#/}/bin/*.{exe,dll})
        message "Bundling DLL dependencies" "${binaries[@]}"
        for binary in "${binaries[@]}"; do
            bundle_dll_dependencies "${binary}"
            unset binary
        done
    fi

    message 'Removing shared library symlinks...'
    find_and_rm -L ${PREFIX#/}/lib -xtype l

    message 'Removing leftover development files...'
    find_and_rm  ${PREFIX#/} ! -type d -name "*.a"
    find_and_rm  ${PREFIX#/} ! -type d -name "*.la"
    rm -rvf ${PREFIX#/}/lib/pkgconfig
    rm -rvf ${PREFIX#/}/include

    # Remove empty directories
    find ${PREFIX#/} -depth -type d -exec rmdir '{}' \; 2>/dev/null

    execute "Archiving ${BUNDLE_DIR%%/}.tar.xz" tar -Jcf "${BUNDLE_DIR%%/}".tar.xz ${PREFIX#/}

    echo -n "popd: "; popd
fi

success 'All packages built successfully'
