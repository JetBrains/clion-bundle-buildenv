#!/bin/bash

set -Eeuo pipefail

# Author: Eldar Abusalimov <Eldar.Abusalimov@jetbrains.com>

# This work is derived from: https://github.com/Alexpux/MINGW-packages
#
# AppVeyor and Drone Continuous Integration for MSYS2
# Author: Renato Silva <br.renatosilva@gmail.com>
# Author: Qian Hong <fracting@gmail.com>

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

error() {
  echo "$*" >&2
  exit 1
}

# https://confluence.jetbrains.com/display/TCD10/Configuring+Build+Parameters
teamcity() {
  echo "##teamcity[$*]"
}

# Basic status function
_status() {
  local type="${1}"
  local status="${package:+${package}: }${2}"
  local items=("${@:3}")

  if [[ -n ${TEAMCITY_VERSION:-} ]]; then
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

# Run command with status
execute() {
  local status="${1}"
  local command="${2}"
  local arguments=("${@:3}")
  block_open "${status}"
  ${command} "${arguments[@]}" || failure "${status} failed"
  block_close "${status}"
}

execute_cd () {
  local d="${1}"
  local status="${2}"
  local command="${3}"
  local arguments=("${@:4}")
  block_open "${status}"
  pushd "${d}" > /dev/null
  ${command} "${arguments[@]}" || failure "${status} failed"
  popd > /dev/null
  block_close "${status}"
}

## Git configuration
#git_config () {
#    local name="${1}"
#    local value="${2}"
#    test -n "$(git config ${name})" && return 0
#    git config --global "${name}" "${value}" && return 0
#    failure 'Could not configure Git for makepkg'
#}

_index_packages() {
  local -r pkg_root_dir=$1

  # index[pkgname] -> ID
  declare -gA _PKG

  local pkgbuild pkgname pkgver pkgrel arch depend makedepends pkg_id

  for pkgbuild in "$pkg_root_dir/"*/PKGBUILD; do
    {
      read -ra pkgnames
      read -r  pkgver
      read -r  pkgrel
      read -ra arch
      read -ra depends
      read -ra makedepends

      for pkgname in "${pkgnames[@]}"; do
        if [ -n "${_PKG[$pkgname]-}" ]; then
          error "$pkgname redefined"
        fi

        if [ -z "${_PKG[*]-}" ]; then
          pkg_id=0
        else
          pkg_id=${#_PKG[@]}
        fi

        _PKG[$pkgname]=$pkg_id

        declare -gr "_PKG_${pkg_id}_pkgname=$pkgname"
        declare -gr "_PKG_${pkg_id}_pkgbuild=$pkgbuild"
        declare -gr "_PKG_${pkg_id}_depends=${depends[*]}"
        declare -gr "_PKG_${pkg_id}_makedepends=${makedepends[*]}"
        declare -gr "_PKG_${pkg_id}_pkgfile=$PKGDEST/$pkgname-$pkgver-$pkgrel-$CARCH$PKGEXT"
        declare -gr "_PKG_${pkg_id}_builddir=$BUILDDIR/${pkgnames[0]}"
      done

      unset pkgname pkgver pkgrel arch depends makedepends
    } < <(
      cd "${pkgbuild%/*}"

      # shellcheck disable=SC1090
      source "$pkgbuild" >/dev/null 2>&1

      # shellcheck disable=SC2154
      {
        echo "${pkgname[@]}"
        echo "$pkgver"
        echo "$pkgrel"
        echo "${arch[@]}"
        echo "${depends[@]}"
        echo "${makedepends[@]}"
      }
    )
  done
}

_get_package_property() {
  local -r package=$1
  local -r property_name=$2

  if [ -z "${_PKG[$package]-}" ]; then
    error "package $package not defined"
  fi

  local -n property="_PKG_${_PKG[$package]}_${property_name}"

  if [ -n "$property" ]; then
    echo "$property"
  fi
}

_get_package_depends_tree() {
  local -r package=$1
  local -r depends_property_name=$2
  local -ra depends=($(_get_package_property "$package" "$depends_property_name"))

  echo "$package"

  local depend; for depend in "${depends[@]}"; do
    _get_package_depends_tree "$depend" "$depends_property_name"
  done
}

_flatten_packages_by_property() {
  local -ra packages=($(printf '%s\n' "${@: 1:$#-1}" | tac))
  local -r property_name=${*: -1:1}
  local -a seen_properties

  local package _property; for package in "${packages[@]}"; do
    _property=$(_get_package_property "$package" "$property_name")

    if echo " ${seen_properties[*]} " | grep -qv " $_property "; then
      echo "$package"
      seen_properties+=("$_property")
    fi
  done
}

_calculate_packages_build_queue() {
  local -ra packages=($*)
  local -a packages_with_makedeps

  local package; for package in "${packages[@]}"; do
    packages_with_makedeps+=($(_get_package_depends_tree $package makedepends))
  done

  _flatten_packages_by_property "${packages_with_makedeps[@]}" pkgbuild
}

_build_package() {
  local -r package=$1
  local -r pkgbuild=$(_get_package_property "$package" pkgbuild)
  local -r pkgfile=$(_get_package_property "$package" pkgfile)
  local -r build_dir=$(_get_package_property "$package" builddir)
  local -ra makedepends=($(_get_package_property "$package" makedepends))
  local -r makedepends_prefix=$build_dir/makedepends

  if [ -f "$pkgfile" ]; then
    return
  fi

  local pkgbuild_dir=${pkgbuild%/*}

  if [ ${#makedepends[@]} -ne 0 ]; then
    mkdir -p "$makedepends_prefix"

    local makedepend makedepend_pkgfile
    for makedepend in "${makedepends[@]}"; do
      makedepend_pkgfile=$(_get_package_property "$makedepend" pkgfile)
      bsdtar -mxvf "$makedepend_pkgfile" -C "$makedepends_prefix"
    done
  fi

  MAKEDEPENDS_PREFIX=$makedepends_prefix \
  execute_cd "$pkgbuild_dir" makepkg makepkg "${MAKEPKG_OPTS[@]}"
}

_bundle_package() {
  local -r package=$1
  local -r builddir=$(_get_package_property "$package" builddir)
  local -ra depends=($(_flatten_packages_by_property $(_get_package_depends_tree "$package" depends) pkgfile))

  local -r bundle_dir=$builddir/bundle
  mkdir -p "$bundle_dir"

  local depend depend_pkgfile; for depend in "${depends[@]}"; do
    depend_pkgfile=$(_get_package_property "$depend" pkgfile)
    bsdtar mxf "$depend_pkgfile" -C "$bundle_dir" --exclude=\.BUILDINFO,\.MTREE,\.PKGINFO
  done

  cd "$bundle_dir"
  bsdtar czf "$DESTDIR/$package.tar.gz" -- *
}

usage() {
  printf -- "Build packages using makepkg and bundle a single archive\n"
  echo
  printf -- "Usage: %s [-c <makepkg.conf>] [OPTION...] [--] [PACKAGE...]\n" "$0"
  echo
  printf -- "Options:\n"
  printf -- "  -c, --config <file>  Use an alternate config file (instead of '%s')\n" "\$pkgroot/makepkg.conf"
  printf -- "  -h, --help           Show this help message and exit\n"
  echo
  printf -- "These options can be passed to %s:\n" "makepkg"
  echo
  printf -- "  --clean              Clean up work files after build\n"
  printf -- "  --cleanbuild         Remove %s dir before building the package\n" "\$package/\$srcdir/"
  printf -- "  -o, --nobuild        Download and extract files only\n"
  printf -- "  -e, --noextract      Do not extract source files (use existing %s dir)\n" "\$package/\$srcdir/"
  printf -- "  -R, --repackage      Repackage contents of the package without rebuilding\n"
  printf -- "  --nocolor            Disable colorized output messages\n"
  echo
}

if [[ $# -eq 0 ]]; then
  usage; exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config)    [[ -n "${2-}" ]] || error "$1: Missing option value"
                    [[ -e "$2" ]]    || error "$2: No such file or directory"
                    MAKEPKG_CONF="$(realpath "$2")"
                    shift ;;

    --clean)        MAKEPKG_OPTS+=("$1") ;;
    --cleanbuild)   MAKEPKG_OPTS+=("$1") ;;
    -o|--nobuild)   MAKEPKG_OPTS+=("$1") ;;
    -e|--noextract) MAKEPKG_OPTS+=("$1") ;;
    -R|--repackage) MAKEPKG_OPTS+=("$1") ;;
    --nocolor)      MAKEPKG_OPTS+=("$1") ;;

    -h|--help)      usage; exit 0 ;;
    -V|--version)   version; exit 0 ;;

    --)             shift; TARGET_PACKAGES=("$@"); break 2;;
    -*)             echo "$1: Unknown option" >&2
                    echo; usage; exit 1 ;;
    *)              TARGET_PACKAGES+=("$1") ;;
  esac
  shift
done

MAKEPKG_OPTS+=(
  --force
  --nodeps
  --nocheck
  --noconfirm
  --skippgpcheck
  --config "$MAKEPKG_CONF"
)

# shellcheck disable=SC1090
source "$MAKEPKG_CONF"

DESTDIR=$PWD/artifacts-$CHOST

# makepkg environmental variables
export PKGDEST=${PKGDEST:-$DESTDIR/makepkg/pkg}      #-- Destination: where all packages will be placed
export SRCDEST=${SRCDEST:-$DESTDIR/makepkg/src}      #-- Source cache: where source files will be cached
export BUILDDIR=${BUILDDIR:-$DESTDIR/makepkg/build}  #-- Build tmp: where makepkg runs package build

_index_packages "${MAKEPKG_CONF%/*}"

build_queue=($(_calculate_packages_build_queue "${TARGET_PACKAGES[@]}"))

for package in "${build_queue[@]}"; do
  _build_package "$package"
done

for target_package in "${TARGET_PACKAGES[@]}"; do
  _bundle_package "$target_package"
done
