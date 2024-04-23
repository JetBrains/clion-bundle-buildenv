source "$(dirname "${BASH_SOURCE[0]}")/makepkg2.conf.inc"

# brew install bash coreutils git libarchive makepkg python3.12 m4 texinfo
export PATH="`
`$(brew --prefix)/opt/coreutils/libexec/gnubin:`
`$(brew --prefix python)/libexec/bin:`
`$(brew --prefix libarchive)/bin:`
`$(brew --prefix m4)/bin:`
`$(brew --prefix texinfo)/bin:`
`$PATH"

# override apple command line tools make with brew
make() { gmake "$@"; }

case "$CARCH" in
  aarch64) _ARCH=arm64;;
  x86_64)  _ARCH=x86_64;;
  *)
    echo "$CARCH is not supported" >&2
    exit 1
  ;;
esac

CHOST=$CARCH-apple-$(clang -dumpmachine | cut -d- -f3)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)

export MACOSX_DEPLOYMENT_TARGET='10.14'

common_flags="-pipe -isysroot $SDKROOT -arch $_ARCH"
export CFLAGS="$common_flags -D_FORTIFY_SOURCE=2 -O2"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="$common_flags"

INSTALL_NAME_TOOL=$(which install_name_tool)

export AR=$(which ar)
export CC=$(which clang)
export CXX=$(which clang++)
export OTOOL=$(which otool)
export STRIP=$(which strip)

tidy_strip() {
  if ! check_option 'strip' 'y'; then
    return
  fi

  msg2 'Removing unneeded symbols and architectures from binaries...'

  local file; while read -r file; do
    if [ "$(file --brief --mime-type "$file" | head -1)" = 'application/x-mach-binary' ]; then
      "$STRIP" -xS "$file"

      if [ "$(lipo -archs "$file")" != "$_ARCH" ]; then
        lipo "$file" -thin "$_ARCH" -output "$file"
      fi
    fi
  done < <(find "$PWD" -type f)
}

enter_fakeroot() {
# brew fakeroot is crashing with brew bash
# look for working bash in PATH and use it
#  local compatible_bash
#
#  while read -r compatible_bash; do
#    if fakeroot -- "$compatible_bash" -c exit; then break; fi
#  done <<<"$(which -a bash)"

  msg "$(gettext "Entering %s environment...")" "fakeroot"
	FAKEROOTKEY="_" bash -$- "${BASH_SOURCE[-1]}" -F "${ARGLIST[@]}" || exit $?
}

remove_framework_versions() {
  local -r framework_dir=$1
  local -r tmp_framework_dir=$(mktemp -d)

  mv "$framework_dir" "$tmp_framework_dir"
  mkdir "$framework_dir"

  cp -r \
    "$tmp_framework_dir/Versions/Current/"* \
    "$framework_dir/"

  rm -rf \
    "$tmp_framework_dir"
}

# remove library version from given file path
strip_library_version() {
  local -r library=$1

  if [[ "$library" =~ (.*/[^.]*).*(\.dylib) ]]; then
    echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  else
    echo "$library"
  fi
}

tidy_library_versions() {
  while read -r file; do
    local type=$(file --brief "$file")

    # remove library versions from all link references
    if [[ "$type" =~ Mach-O.*(shared.*library|bundle|executable) ]]; then
      "$OTOOL" -l "$file" | grep LC_LOAD_DYLIB -A2 | grep name | while read -r _ library _; do
        local library_without_version=$(strip_library_version "$library")

        # only check for libraries provided by package itself or dependencies
        local library_new=
        if [[ "$library" == "$PREFIX"* ]]; then
          library_new=${library_without_version/$PREFIX/@rpath}
        elif [ -f "$MAKEDEPENDS_PREFIX/${library#$PREFIX}" ]; then
          library_new="@rpath${library_without_version#$PREFIX}"
        fi

        if [ -n "$library_new" ]; then
          msg2 "Change install name in $file: $library -> $library_new"
          "$INSTALL_NAME_TOOL" "$file" -change "$library" "$library_new"
        fi
      done
    fi

    # remove library versions from file names and set rpath relative ids
    if [[ "$type" =~ Mach-O.*(shared.*library|bundle) ]]; then
      local library_without_version=$(strip_library_version "$file")

      if [ ! "$file" = "$library_without_version" ]; then
        msg2 "Renaming $file to $library_without_version"
        mv "$file" "$library_without_version"
        "$INSTALL_NAME_TOOL" "$library_without_version" \
          -id "@rpath/${library_without_version#"$pkgdir$PREFIX/"}"
      fi
    fi

    # add rpath to executables
    if [[ "$type" =~ Mach-O.*executable ]]; then
      "$INSTALL_NAME_TOOL" "$file" -add_rpath "@executable_path/.."
    fi
  done < <(find $PWD -type f)
}

tidy_symlinks() {
  while read -r symlink; do
    msg2 "Removing symlink: $symlink"
    rm -rf "$symlink"
  done < <(find . -type l)
}

tidy_install() {
  tidy_install_original
  tidy_symlinks
  tidy_library_versions
  tidy_prefix
}

install_for_package() {
  local target=${1-install}
  local install_dir_spec=${2-DESTDIR}

  make "$install_dir_spec=$(temp_destdir)" $target -j {V,VERBOSE}=1
}

package_dev() {
  local package_dev_name=${1-${pkgname[1]}}

  source /dev/stdin <<-EOF
    package_$package_dev_name() {
      cd "\$(temp_destdir)"

      while read -r dylib; do
        install -D "\$dylib" "\$pkgdir/\$dylib"
      done< <(find "./\$PREFIX/lib" -maxdepth 1 -type f -name \*\.dylib)

      if [ -d "./\$PREFIX/lib/pkgconfig" ]; then
        cp -r "./\$PREFIX/lib/pkgconfig" "\$pkgdir\$PREFIX/lib/pkgconfig"
      fi

      cp -r "./\$PREFIX/include" "\$pkgdir\$PREFIX/include"
    }
EOF
}

package_dylib_with_dev() {
  local package_name=${1-${pkgname[0]}}
  local package_dev_name=${2-${pkgname[1]}}

  source /dev/stdin <<-EOF
    package_$package_name() {
      cd "\$(temp_destdir)"

      while read dylib; do
        ginstall -D "\$dylib" "\$pkgdir/\$dylib"
      done< <(find "./\$PREFIX/lib" -maxdepth 1 -type f -name \*\.dylib)

      if [ -d "./\$PREFIX/share" ]; then
        cp -r "./\$PREFIX/share" "\$pkgdir\$PREFIX/share"
      fi
    }
EOF

  package_dev
}

package_application_with_dev() {
  local package_name=${1-${pkgname[0]}}
  local package_dev_name=${2-${pkgname[1]}}

  source /dev/stdin <<-EOF
    package_$package_name() {
      mkdir -p "\$pkgdir\$PREFIX"
      local dir; for dir in "bin" "lib" "share"; do
        cp -r "\$(temp_destdir)\$PREFIX/\$dir" "\$pkgdir\$PREFIX/\$dir"
      done
    }
EOF

  package_dev
}

apply_patches() {
  local source

  for source in "${source[@]}"; do
    if [[ "$source" == *.patch  ]]; then
      msg2 "Applying patch %s" "$source"
      patch -p1 <"$srcdir/$source"
    fi
  done
}
