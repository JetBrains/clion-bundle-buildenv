PREFIX=${PREFIX-/win}

# Keep static archives, libtool archives, pkgconfig and the toolchain include
# tree in the bundle.  On Windows the *.a/*.dll.a files are not just static
# libs — they are import libs the linker needs to resolve every -l<name> flag
# (Win32: -lkernel32, -luser32, ...; GCC runtime: -lstdc++, -lssp, -latomic,
# -lgomp, -lwinpthread, ...).  Without them the bundled toolchain cannot link
# anything at all.
KEEP_DEV_FILES=1

_makepkg_mingw_conf_name="${BASH_SOURCE}"

source $(dirname ${_makepkg_mingw_conf_name})/../makepkg.conf.inc

BUILDENV+=(ccache)

# Override strip to use the tool from cross-toolchain
tidy_strip() {
	if check_option "strip" "y"; then
		msg2 "$(gettext "Stripping unneeded symbols from binaries and libraries...") [OVERRIDDEN in ${_makepkg_mingw_conf_name}]"
		# make sure library stripping variables are defined to prevent excess stripping
		[[ -z ${STRIP_SHARED+x} ]] && STRIP_SHARED="-S"
		[[ -z ${STRIP_STATIC+x} ]] && STRIP_STATIC="-S"

		# if check_option "debug" "y"; then

		# 	dbgdir="$pkgdirbase/$pkgbase-@DEBUGSUFFIX@/usr/lib/debug"
		# 	dbgsrc="$pkgdirbase/$pkgbase-@DEBUGSUFFIX@/usr/src/debug"
		# 	mkdir -p "$dbgdir" "$dbgsrc"
		# fi

		local binary strip_flags
		find . -type f -perm -u+w -print0 2>/dev/null | while read -rd '' binary ; do
			case "$(file -bi "$binary")" in
				*application/x-dosexec*)  # Libraries (.dll) and Binaries (.exe)
					strip_flags="$STRIP_SHARED";;
				*application/x-archive*)    # Libraries (.a)
					strip_flags="$STRIP_STATIC";;
				# *application/x-object*)
				# 	case "$binary" in
				# 		*.ko)                   # Kernel module
				# 			strip_flags="$STRIP_SHARED";;
				# 		*)
				# 			continue;;
				# 	esac;;
				# *application/x-executable*) # Binaries
				# 	strip_flags="$STRIP_BINARIES";;
				*)
					continue ;;
			esac
			${CHOST}-strip ${strip_flags} "$binary"
		done
	fi
}

apply_patches() {
	local p s
	for p in "${srcdir}/"*.patch; do
		[[ -f "$p" ]] || continue
		echo "Applying ${p}"
		for s in 1 2 3; do
			if patch --dry-run -p${s} -i "${p}" &>/dev/null; then
				patch -p${s} -i "${p}"
				continue 2
			fi
		done
		echo "error: patch failed at all strip levels: ${p}" >&2
		return 1
	done
}

# Apply patches from srcdir that match a glob, targeting a subdirectory of the
# source tree.  Patches that don't apply in the given subdir are silently
# skipped — they belong to a different directory.
apply_patches_matching() {
	local glob="$1" subdir="$2"
	local target_dir="${srcdir}/${pkgname}-${pkgver}/${subdir}"
	local p s applied=0

	[[ -d "$target_dir" ]] || return 0

	for p in "${srcdir}/"${glob}; do
		[[ -f "$p" ]] || continue
		for s in 1 2 3; do
			if patch --dry-run -d "$target_dir" -p${s} -i "${p}" &>/dev/null; then
				echo "Applying ${p##*/} in ${subdir:-.}"
				patch -d "$target_dir" -p${s} -i "${p}"
				((++applied))
				continue 2
			fi
		done
	done

	if [[ $applied -eq 0 && "$subdir" != "." ]]; then
		echo "note: no patches applied in ${subdir}"
	fi
}

install_copying() {
	find "${srcdir}" -type f -name "COPYING*" | while read c; do
		install -Dm644 -t "${pkgdir}${PREFIX}/licenses/${pkgname}" "${c}"
	done
}

# Hook called by build.sh do_bundle() inside ${BUNDLE_DIR} to apply mingw-only
# shaping to the extracted prefix tree before archiving.  Two responsibilities:
#
#   1. Bring in payload from packages that are otherwise makedepends-only.
#      The bundled toolchain needs:
#        - manifest:           default-manifest.o (referenced by gcc specs at
#                              link time for every produced executable)
#        - zlib, libiconv:     headers + static libs that gcc/binutils were
#                              built against; users compiling against the
#                              cross-toolchain expect them in the sysroot
#        - gmp, mpc, mpfr:     statically linked into gcc; their COPYING
#                              files must travel with the bundle (LGPL/GPL)
#
#   2. Relocate libgcc_s files so gcc's specs find them.  Upstream installs
#      libgcc_s_seh-1.dll under lib/gcc/${CHOST}/ and libgcc_s.a under
#      lib/gcc/${CHOST}/lib/, but gcc's compiled-in spec searches the
#      version-numbered subdir for the import lib and Windows DLL search
#      finds the runtime DLL via PATH (so it has to live in bin/).
finalize_bundle() {
	local package
	for package in manifest zlib libiconv gmp mpc mpfr; do
		execute "extract (makedep)" \
			bsdtar -xvf "${PKGDEST}/$(pkgfilename)" ${PREFIX#/}
	done
	unset package

	local gcc_libdir="${PREFIX#/}/lib/gcc/${CHOST}"
	local gcc_ver_libdir
	gcc_ver_libdir=$(ls -d "${gcc_libdir}"/[0-9]*.[0-9]*.[0-9]* 2>/dev/null | head -n1)
	if [[ -n "${gcc_ver_libdir}" && -f "${gcc_libdir}/lib/libgcc_s.a" ]]; then
		mv -v "${gcc_libdir}/lib/libgcc_s.a" "${gcc_ver_libdir}/"
		rmdir "${gcc_libdir}/lib" 2>/dev/null || true
	fi
	if [[ -f "${gcc_libdir}/libgcc_s_seh-1.dll" ]]; then
		mv -v "${gcc_libdir}/libgcc_s_seh-1.dll" "${PREFIX#/}/bin/"
	fi
}

# vim: set ft=sh ts=2 sw=2 et: