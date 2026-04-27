#!/bin/bash
# Source a PKGBUILD with MSYS2 variables stubbed out and print
# pkgver, source[], and sha256sums[] as tab-separated lines.
#
# Output format:
#   PKGVER\t<version>
#   SOURCE\t<url-or-filename>
#   SHA256\t<checksum>
#
# Usage: parse-pkgbuild.sh <path-to-PKGBUILD>

export MINGW_PACKAGE_PREFIX="mingw-w64-x86_64"
export MSYSTEM="MINGW64"
export MINGW_PREFIX="/mingw64"
export MINGW_CHOST="x86_64-w64-mingw32"
export CARCH="x86_64"
_realname=""
check_option() { return 1; }
msg2() { :; }

source "$1" 2>/dev/null || true

printf 'PKGVER\t%s\n' "$pkgver"
for s in "${source[@]}"; do printf 'SOURCE\t%s\n' "$s"; done
for s in "${sha256sums[@]}"; do printf 'SHA256\t%s\n' "$s"; done
