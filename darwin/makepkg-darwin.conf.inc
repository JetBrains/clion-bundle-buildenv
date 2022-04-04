PREFIX=${PREFIX-/darwin}

_makepkg_mingw_conf_name="${BASH_SOURCE}"

source $(dirname ${_makepkg_mingw_conf_name})/../makepkg.conf.inc

BUILDENV+=(ccache)

tidy_strip() {
  if ! check_option "strip" "y"; then
    return
  fi

  msg2 "Stripping unneeded symbols from binaries and libraries... `
       `[OVERRIDDEN in ${_makepkg_mingw_conf_name}]"

  local executable
  while read executable; do
    if file -bi "$executable" | grep -q 'application/x-mach-binary'; then 
      $CHOST-strip -x -S "$executable"
    fi
  done <<<$(
    find . -type f -perm -u+w
  )
}

install_copying() {
  find "${srcdir}" -type f -name "COPYING*" | while read c; do
    install -Dm644 -t "${pkgdir}${PREFIX}/licenses/${pkgname}" "${c}"
  done
}

remove_framework_versions() {
  local framework_dir=$1
  local tmp_framework_dir=$(mktemp -d)

  mv "$framework_dir" "$tmp_framework_dir"
  mkdir "$framework_dir"

  cp -r \
    "$tmp_framework_dir/Versions/Current/"* \
    "$framework_dir/"

  rm -rf \
    "$tmp_framework_dir"
}


strip_library_version() {
  local library=$1

  if [[ "${library,,}" == *".dylib" ]]; then 
    echo "${library%/*}/$(echo ${library##*/} | cut -d. -f1).${library##*.}"
  else
    echo $library
  fi
}

fix_install() {
  local install_dir=$1
  set -x

  rm -rf "$install_dir/share/"{doc,man}

  find "$install_dir" -type l \
      | while read symlink; do
    msg2 "Removing $symlink"
    rm -rf "$symlink"
  done

  find "$install_dir" -type f -executable | while read file; do
    type=$(file --brief "$file")

    if [[ "$type" =~ Mach-O.*(shared.*library|bundle|executable) ]]; then
      "$CHOST-otool" -l "$file" | grep LC_LOAD_DYLIB -A2 | grep name \
          | while read _ library _; do
        for ref_dir in "$MAKEDEPENDS" "$install_dir"; do
          local library_without_version=$(strip_library_version $library)
          local library_new=

          if [[ "$library" == "$ref_dir"* ]]; then
            library_new=$(echo "$library_without_version" | sed "s|$ref_dir|@rpath|")
          elif [ -f "$ref_dir/$library" ]; then
            library_new="@rpath$library_without_version"
          fi

          if [ -n "$library_new" ]; then
            $CHOST-install_name_tool "$file" -change "$library" "$library_new"
          fi
        done
      done
    fi

    if [[ "$type" =~ Mach-O.*(shared.*library|bundle) ]]; then
      local library_without_version=$(strip_library_version $file)

      if [ ! "$file" == "$library_without_version" ]; then
        msg2 "Renaming $file to $library_without_version"

        mv "$file" "$library_without_version"
        $CHOST-install_name_tool "$library_without_version" \
          -id "@rpath/${library_without_version#$install_dir/}"
      fi
    fi
    
    if [[ "$type" =~ Mach-O.*executable ]]; then
        $CHOST-install_name_tool "$file" -add_rpath "@executable_path/.."
    fi
  done
}

install_for_package() { 
  local target=${1-install}
  local install_dir_spec=${2-DESTDIR}

  local install_dir="$srcdir/_install"
  make "$install_dir_spec=$install_dir" $target -j {V,VERBOSE}=1

  fix_install "$install_dir"
}

package_dev() {
  local package_dev_name=${1-${pkgname[1]}}

  source /dev/stdin <<-EOF
    function package_${package_dev_name}() {
      depends=($package_name)
      local install_dir="\$srcdir/_install"

      find "\$install_dir/lib" -maxdepth 1 -type f -name \*\.dylib \
          | while read dylib; do
        install -D "\$dylib" "\$pkgdir/\${dylib#\$install_dir/}"
      done

      if [ -d "\$install_dir/lib/pkgconfig" ]; then
        cp -r "\$install_dir/lib/pkgconfig" \
          "\$pkgdir/lib/pkgconfig"
      fi

      cp -r "\$install_dir/include" \
         "\$pkgdir/include"
    }
EOF
}

package_dylib_with_dev() {
  local package_name=${1-${pkgname[0]}}
  local package_dev_name=${2-${pkgname[1]}}

  source /dev/stdin <<-EOF
    function package_${package_name}() {
      local install_dir="\$srcdir/_install"

      find "\$install_dir/lib" -maxdepth 1 -type f -name \*\.dylib \
          | while read dylib; do
        install -D "\$dylib" "\$pkgdir/\${dylib#\$install_dir/}"
      done

      if [ -d "\$install_dir/share" ]; then
        cp -r "\$install_dir/share" \
          "\$pkgdir/share"
      fi
    }
EOF

  package_dev
}

package_application_with_dev() {
  local package_name=${1-${pkgname[0]}}
  local package_dev_name=${2-${pkgname[1]}}

  source /dev/stdin <<-EOF
    function package_${package_name}() {
      local install_dir="\$srcdir/_install"

      cp -r "\$install_dir/lib" \
        "\$pkgdir/lib"
      
      cp -r "\$install_dir/bin" \
        "\$pkgdir/bin"
      
      cp -r "\$install_dir/share" \
        "\$pkgdir/share"
    }
EOF

  package_dev
}

apply_patches() {
	local p s="${1:-1}"

	for p in "${srcdir}/"*.patch; do
		echo "Applying ${p}"
		patch -p${s} -i "${p}"
	done
}