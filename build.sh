#!/bin/bash

set -e -o pipefail

# Author: Eldar Abusalimov <Eldar.Abusalimov@jetbrains.com>

# This work is derived from: https://github.com/Alexpux/MINGW-packages
#
# AppVeyor and Drone Continuous Integration for MSYS2
# Author: Renato Silva <br.renatosilva@gmail.com>
# Author: Qian Hong <fracting@gmail.com>

prog_version=0.2


if tput init >/dev/null 2>&1; then
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

function error() (
    echo $@ >&2
    exit 1
    kill -9 $$ 2>/dev/null
)

# https://confluence.jetbrains.com/display/TCD10/Configuring+Build+Parameters
teamcity() {
    echo "##teamcity[$@]"
}

# Basic status function
_status() {
    local type="${1}"
    local status="${package:+${package}: }${2}"
    local items=("${@:3}")

    if [[ -n ${TEAMCITY_VERSION} ]]; then
        case "${type}" in
            block_open)  local teamcity_args="blockOpened name='${status}'" ;;
            block_close) local teamcity_args="blockClosed name='${status}'" ;;
            message)     local teamcity_args="message text='${status}'" ;;
            failure)     local teamcity_args="buildProblem description='${status}'" ;;
            success)     return 0 ;;  # skip it, TC will set the default "Success" badge by default
        esac
        teamcity "${teamcity_args}"
        printf "${items:+\t%s\n}" "${items:+${items[@]}}"
    else
        case "${type}" in
            block_close) return 0 ;;  # don't report when running from terminal
            block_open|message)
                     local color="${cyan}";  title='[BUILD]' ;;
            failure) local color="${red}";   title='[BUILD] FAILURE:' ;;
            success) local color="${green}"; title='[BUILD] SUCCESS:' ;;
        esac
        echo "${color}${title}${normal} ${status}" >&2
        printf "${items:+\t%s\n}" "${items:+${items[@]}}" >&2
    fi
}

# Status functions
failure() { local status="${1}"; local items=("${@:2}"); _status failure "${status}" "${items[@]}"; exit 1; }
success() { local status="${1}"; local items=("${@:2}"); _status success "${status}" "${items[@]}"; exit 0; }
message() { local status="${1}"; local items=("${@:2}"); _status message "${status}" "${items[@]}"; }
block_open()  { local status="${1}"; local items=("${@:2}"); _status block_open  "${status}"  "${items[@]}"; }
block_close() { local status="${1}"; local items=("${@:2}"); _status block_close "${status}"  "${items[@]}"; }


# Git configuration
git_config() {
    local name="${1}"
    local value="${2}"
    test -n "$(git config ${name})" && return 0
    git config --global "${name}" "${value}" && return 0
    failure 'Could not configure Git for makepkg'
}

_index_packages() {
    local pkg_root_dir=$1
    local makepkg_config=$2

    declare -Ag _PKG

    local property_names=(
        depends
        makedepends
        # custom:
        # pkgname = splitted pkgname
        # pkgbuild = path to pkgbuild
        # pkgfile = package filename
        # builddir = 
    )
    
    local pkgbuild
    for pkgbuild in "${pkg_root_dir}/"*/PKGBUILD; do
        {
            declare ${property_names[@]}
            local pkgnames pkgfile_suffix
            read -a pkgnames
            read pkgfile_suffix

            local line
            while read -r line; do
                declare -a "${line%%:*}=(${line#*:})"
            done

            local pkgname 
            for pkgname in ${pkgnames[@]}; do
                if [ -n "${_PKG[$pkgname]-}" ]; then
                    error "$pkgname redefined"
                else
                    local package_id=${#_PKG[@]}
                    _PKG[$pkgname]=$package_id

                    declare -rg "_PKG_${package_id}_pkgname=$pkgname"
                    declare -rg "_PKG_${package_id}_pkgbuild=$pkgbuild"
                    declare -rg "_PKG_${package_id}_pkgfile=$PKGDEST/$pkgname$pkgfile_suffix"
                    declare -rg "_PKG_${package_id}_builddir=$BUILDDIR/$pkgnames"

                    local property_name
                    for property_name in ${property_names[@]}; do
                        declare -n "property=$property_name"
                        declare -rg "_PKG_${package_id}_${property_name}=${property[*]}"
                    done
                fi
            done

            unset ${property_names[@]}
        }<<<$(
            cd "${pkgbuild%/*}"

            {
                set +u
                source "$makepkg_config"
                source "$pkgbuild"
            } >/dev/null 2>&1

            echo "${pkgname[@]}"

            if [[ $arch != "any" ]]; then
                arch="$CARCH"
            fi

            echo "-$pkgver-$pkgrel-$arch$PKGEXT"

            local property_name
            for property_name in ${property_names[@]}; do
                declare -n "property=$property_name"
                echo "$property_name:${property[*]}"
            done
        )
    done
}

_get_package_property() {
    local package=$1
    local property_name=$2

    if [ -z "${_PKG[$package]-}" ]; then
        error "package $package not defined"
    fi
    
    local property="_PKG_${_PKG[$package]}_${property_name}"

    if [ -z "${!property+x}" ]; then
        error "package $package does not have $property_name property"
    fi

    echo "${!property}"
}

_get_package_depends_tree() {
    local package=$1
    local depends_property_name=$2

    local depends=($(_get_package_property $package $depends_property_name))

    echo $package

    local depends
    for depend in ${depends[@]}; do
        _get_package_depends_tree $depend $depends_property_name
    done
}

_flatten_packages_by_property() {
    local packages=($(printf '%s\n' "${@: 1:$#-1}" | tac))
    local property_name=${@: -1:1}

    declare -a seen_properties 

    for package in ${packages[@]}; do
        local _property=$(_get_package_property $package $property_name)
        
        if ! [[ " ${seen_properties[*]} " =~ " $_property " ]]; then
            echo $package
            seen_properties+=$_property
        fi
    done
}

# Run command with status
execute(){
    local status="${1}"
    local command="${2}"
    local arguments=("${@:3}")
    block_open "${status}"
    ${command} ${arguments[@]} || failure "${status} failed"
    block_close "${status}"
}

execute_cd(){
    local d="${1}"
    local status="${2}"
    local command="${3}"
    local arguments=("${@:4}")
    block_open "${status}"
    pushd "${d}" > /dev/null
    ${command} ${arguments[@]} || failure "${status} failed"
    popd > /dev/null
    block_close "${status}"
}


usage() {
    printf "%s %s\n" "$0" "$prog_version"
    echo
    printf -- "Build packages using makepkg and bundle a single archive\n"
    echo
    printf -- "Usage: %s [-P <pkgroot>] [-c <makepkg.conf>] [OPTION...] [--] [PACKAGE...]\n" "$0"
    echo
    printf -- "Options:\n"
    printf -- "  -P, --pkgroot <dir>  Directory to search packages in (instead of '%s')\n" "\$CWD"
    printf -- "  -c, --config <file>  Use an alternate config file (instead of '%s')\n" "\$pkgroot/makepkg.conf"
    printf -- "  --nomakepkg          Do not rebuild packages\n"
    printf -- "  --noinstall          Do not extract packages into '%s'\n" "\$PREFIX"
    printf -- "  --nobundle           Do not create '%s' from package files\n" "\$DESTDIR/bundle.tar.xz"
    printf -- "  --nodeps             Do not build or bunble dependencies\n"
    printf -- "  --onlydeps           Build or bunble only dependencies, useful with --nomakepkg --nobundle\n"
    printf -- "  -h, --help           Show this help message and exit\n"
    printf -- "  -V, --version        Show version information and exit\n"
    echo
    printf -- "These options can be passed to %s:\n" "makepkg"
    echo
    printf -- "  --clean              Clean up work files after build\n"
    printf -- "  --cleanbuild         Remove %s dir before building the package\n" "\$package/\$srcdir/"
    printf -- "  -g, --geninteg       Generate integrity checks for source files (implies --noinstall --nobundle)\n"
    printf -- "  -o, --nobuild        Download and extract files only\n"
    printf -- "  -e, --noextract      Do not extract source files (use existing %s dir)\n" "\$package/\$srcdir/"
    printf -- "  -R, --repackage      Repackage contents of the package without rebuilding\n"
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
    printf -- "  CCACHE_DIR           where to keep ccache'd outputs     [ \$DESTDIR/ccache ]\n"
    echo
}

version() {
    printf "%s %s\n" "$0" "$prog_version"
    makepkg --version
}

if [[ $# -eq 0 ]]; then
    usage; exit -1
fi

MAKEPKG_CONF=
PKG_ROOT_DIR=

set_file_option() {
    local varname="$1" option="$2" value="$3"
    [[ -n "${value}" ]] || error "${option}: Missing option value"
    [[ -e "${value}" ]] || error "${value}: No such file or directory"

    eval "${varname}=\"\${value}\""
}

MAKEPKG_OPTS=(--force --noconfirm --skippgpcheck --nocheck --nodeps)

NOMAKEPKG=0
NOBUNDLE=0
NODEPS=0
ONLYDEPS=0
NOINSTALL=0
LOGGING=0

target_packages=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -P|--pkgroot)     set_file_option PKG_ROOT_DIR "$1" "$2"; shift ;;
        -P=*|--pkgroot=*) set_file_option PKG_ROOT_DIR "${1%%=*}" "${1#*=}" ;;

        -c|--config)      set_file_option MAKEPKG_CONF "$1" "$2"; shift ;;
        -c=*|--config=*)  set_file_option MAKEPKG_CONF "${1%%=*}" "${1#*=}" ;;

        # Makepkg Options
        --clean)          MAKEPKG_OPTS+=($1) ;;
        --cleanbuild)     MAKEPKG_OPTS+=($1) ;;
        -g|--geninteg)    MAKEPKG_OPTS+=($1); NOBUNDLE=1; NOINSTALL=1 ;;
        -o|--nobuild)     MAKEPKG_OPTS+=($1); ;;
        -e|--noextract)   MAKEPKG_OPTS+=($1) ;;
        -R|--repackage)   MAKEPKG_OPTS+=($1) ;;
        -L|--log)         MAKEPKG_OPTS+=($1); LOGGING=1 ;;
        --nocolor)        MAKEPKG_OPTS+=($1) ;;

        --nomakepkg)      NOMAKEPKG=1 ;;
        --noinstall)      NOINSTALL=1 ;;
        --nobundle)       NOBUNDLE=1 ;;
        --nodeps)         NODEPS=1 ;;
        --onlydeps)       ONLYDEPS=1 ;;

        -h|--help)        usage; exit 0 ;; # E_OK
        -V|--version)     version; exit 0 ;; # E_OK

        --)               OPT_IND=0; shift; break 2;;
        -*)               echo "${1}: Unknown option" >&2
                          echo; usage; exit -1 ;;
        *)                target_packages+=("$1") ;;
    esac
    shift
done

target_packages+=("$@")

PKG_ROOT_DIR="${PKG_ROOT_DIR:-$(pwd)}"
if [ ! -d "${PKG_ROOT_DIR}" ]; then
    error "${PKG_ROOT_DIR}: Directory doesn't exist"
fi
export PKG_ROOT_DIR=$(realpath "${PKG_ROOT_DIR}")

MAKEPKG_CONF="${MAKEPKG_CONF:-${PKG_ROOT_DIR}/makepkg.conf}"
if [ ! -f "${MAKEPKG_CONF}" ]; then
    error "${MAKEPKG_CONF}: File not found"
fi
export MAKEPKG_CONF=$(realpath "${MAKEPKG_CONF}")

source "${MAKEPKG_CONF}"

MAKEPKG_OPTS+=(--config "${MAKEPKG_CONF}")


[[ -n ${CHOST} ]] || CHOST=$(gcc -dumpmachine)
[[ "${CHOST}" == *-w64-mingw* ]] && ISMINGW=1 || ISMINGW=0

if [ ! -n "${PREFIX}" ]; then
    failure "${MAKEPKG_CONF}: Missing \$PREFIX variable definition"
fi
export PATH="$PATH:$PREFIX/bin"

# makepkg environmental variables
export DESTDIR=$PWD/${DESTDIR:-artifacts-${CHOST}}
export PKGDEST=${PKGDEST:-${DESTDIR}/makepkg/pkg}      #-- Destination: where all packages will be placed
export SRCDEST=${SRCDEST:-${DESTDIR}/makepkg/src}      #-- Source cache: where source files will be cached
export LOGDEST=${LOGDEST:-${DESTDIR}/makepkg/log}      #-- Log files: where all log files will be placed
export BUILDDIR=${BUILDDIR:-${DESTDIR}/makepkg/build}  #-- Build tmp: where makepkg runs package build

export CCACHE_DIR=${CCACHE_DIR:-${DESTDIR}/ccache}     #-- where ccache will keep its cached compiler outputs

export CCACHE_BASEDIR=${BUILDDIR}
export CCACHE_COMPILERCHECK=content

_index_packages $PKG_ROOT_DIR $MAKEPKG_CONF 

BUNDLE_DIR="${DESTDIR}/bundle"
BUNDLE_TARBALL="${BUNDLE_DIR%%/}".tar.xz

mkdir -p "${DESTDIR}" "${PKGDEST}" "${SRCDEST}" || failure "Couldn't create directories"
if (( LOGGING )); then
    mkdir -p "${LOGDEST}" || failure "Couldn't create directories"
fi

git_config user.name  "${GIT_COMMITTER_NAME}"
git_config user.email "${GIT_COMMITTER_EMAIL}"

# export TMPDIR=$(mktemp -d)
# trap "rm -rf ${TMPDIR}" INT QUIT TERM HUP EXIT

export PACMAN=false  # just to be sure makepkg won't call it


_calculate_packages_build_queue() {
    local packages=($@)
    local packages_with_makedeps=()

    local package
    for package in ${packages[@]}; do
        packages_with_makedeps+=(
            $(_get_package_depends_tree $package makedepends)
        )
    done

    _flatten_packages_by_property ${packages_with_makedeps[@]} pkgbuild
}

_build_package() {
    local package=$1
    local pkgbuild=$(_get_package_property $package pkgbuild)
    local pkgfile=$(_get_package_property $package pkgfile)
    local builddir=$(_get_package_property $package builddir)
    local makedepends=($(_get_package_property $package makedepends))

    if [ -f $pkgfile ]; then
        return
    fi

    local pkgbuild_dir=${pkgbuild%/*}
    local makedepends_dir=$builddir/makedepends

    mkdir -p $makedepends_dir

    local makedepend
    for makedepend in ${makedepends[@]}; do
        local makedepend_pkgfile=$(_get_package_property $makedepend pkgfile)
        bsdtar -mxvf $makedepend_pkgfile -C $makedepends_dir
    done

    MAKEDEPENDS=$makedepends_dir \
    execute_cd "${pkgbuild_dir}" makepkg \
        makepkg "${MAKEPKG_OPTS[@]}" --config "${MAKEPKG_CONF}"

    chmod 755 "$builddir/pkg"
}

_bundle_package() {
    local package=$1
    local builddir=$(_get_package_property $package builddir)
    local depends=($(
        _flatten_packages_by_property $(
            _get_package_depends_tree $package depends
        ) pkgfile
    ))

    local bundle_dir=$builddir/bundle
    mkdir -p $bundle_dir

    local depend
    for depend in ${depends[@]}; do
        local depend_pkgfile=$(_get_package_property $depend pkgfile)
        bsdtar -mxvf $depend_pkgfile -C $bundle_dir \
            --exclude=\.BUILDINFO,\.MTREE,\.PKGINFO
    done

    cd $bundle_dir
    mkdir -p $BUNDLE_DIR
    bsdtar -cvzf $BUNDLE_DIR/$package-bundle.tar.gz * 
}

build_queue=$(_calculate_packages_build_queue ${target_packages[@]})

for package in ${build_queue[@]}; do
    _build_package $package
done

for target_package in ${target_packages[@]}; do
    _bundle_package $target_package
done
