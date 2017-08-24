#!/bin/bash

# Author: Eldar Abusalimov <Eldar.Abusalimov@jetbrains.com>

# This work is derived from: https://github.com/Alexpux/MINGW-packages
#
# AppVeyor and Drone Continuous Integration for MSYS2
# Author: Renato Silva <br.renatosilva@gmail.com>
# Author: Qian Hong <fracting@gmail.com>

prog_version=0.1

export BUILD_ROOT_DIR="$(dirname $(readlink -e "${0}"))"

source "${BUILD_ROOT_DIR}/libbuild.sh"


usage() {
    printf "%s %s\n" "$0" "$prog_version"
    echo
    printf -- "Build packages using makepkg and bundle a single archive\n"
    echo
    printf -- "Usage: %s -c <makepkg.conf> [package...]\n" "$0"
    echo
    printf -- "Options:\n"
    printf -- "  -c, --config <file>  Use an alternate config file (instead of '%s')\n" "$confdir/makepkg.conf"
    printf -- "  --nomakepkg          Do not rebuild packages\n"
    printf -- "  --nobundle           Do not create %s from package files\n" "\$artifactsdir/bundle-\$chost.tar.xz"
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

ARTIFACTS_DIR="$(readlink -m "artifacts")"
deploy_enabled && [ -d "${ARTIFACTS_DIR}" ] || mkdir -p "${ARTIFACTS_DIR}"

git_config user.name  "${GIT_COMMITTER_NAME}"
git_config user.email "${GIT_COMMITTER_EMAIL}"

export TMPDIR=$(mktemp -d)
set_on_error_trap "rm -rf ${TMPDIR}"


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

if (( ! NOMAKEPKG )); then
    # Build
    message 'Building packages' "${packages[@]}"

    for package in "${packages[@]}"; do
        export PACMAN=false  # just to be sure makepkg won't call it
        execute_cd "${package}" 'Building binary' makepkg "${MAKEPKG_OPTS[@]}" --config "${MAKEPKG_CONF}"

        if (( ! NODEPLOY )); then
            deploy_enabled && [[ -f "${package}"/*-debug-*${PKGEXT} ]] \
                           && mv -f "${package}"/*-debug-*${PKGEXT} "${ARTIFACTS_DIR}"
            execute_cd "${package}" 'Installing' tar xvf $(get_pkgfile "${package}") -C / ${PREFIX#/}
            deploy_enabled && mv -f "${package}"/$(get_pkgfile "${package}") "${ARTIFACTS_DIR}"
        fi
        unset package
    done


    if (( ! NODEPLOY )); then
        if [[ "${CHOST}" == *-w64-mingw* ]]; then
            for package in "${target_packages[@]}"; do
                package_runtime_dependencies ${package}
                deploy_enabled && mv -f "${package}"/*-dll-dependencies.tar.xz "${ARTIFACTS_DIR}" 2>/dev/null || true
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
