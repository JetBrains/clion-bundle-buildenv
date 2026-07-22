PREFIX=${PREFIX-/win}

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

# vim: set ft=sh ts=2 sw=2 et: