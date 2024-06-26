#
# Common bits for makepkg.conf.inc
#

#set -Eexuo pipefail

PACMAN=false  # to be sure makepkg won't call it
QUIET=0       # do not suppress msg2's

# some tools require it to be real, but
# we are not going to write anything there
PREFIX=/usr/local

# back up function implementations to
copy_functions() {
  local -r function_names=($@)

  local function_name; for function_name in "${function_names[@]}"; do
    function=$(declare -f "$function_name")
    eval "${function_name}_original${function#"$function_name"}"
  done
}

if [ -n "${MAKEPKG_LIBRARY-}" ]; then
  copy_functions tidy_install
fi

tidy_prefix() {
  msg2 "Removing install prefix..."
  mv "$pkgdir$PREFIX"/* "$pkgdir"
  rm -rf "$pkgdir/$(echo "$PREFIX" | cut -d '/' -f2)"
}

# sometimes it's easier & cleaner to "make install"
# into a temporary directory right after build and
# collect and copy specific contents from it into a
# split package dedicated pkgdirs
temp_destdir() {
  # shellcheck disable=SC2154
  echo "$srcdir/dest-$CHOST"
}

PKGVERSION="JetBrains IDE bundle${BUILD_NUMBER:+; build ${BUILD_NUMBER}}"

#########################################################################
# SOURCE ACQUISITION
#########################################################################
#
#-- The download utilities that makepkg should use to acquire sources
#  Format: 'protocol::agent'
DLAGENTS=('ftp::/usr/bin/curl -fC - --ftp-pasv --retry 3 --retry-delay 3 -o %o %u'
          'http::/usr/bin/curl -qb "" -fLC - --retry 3 --retry-delay 3 -o %o %u'
          'https::/usr/bin/curl -qb "" -fLC - --retry 3 --retry-delay 3 -o %o %u'
          'rsync::/usr/bin/rsync --no-motd -z %u %o'
          'scp::/usr/bin/scp -C %u %o')

# Other common tools:
# /usr/bin/snarf
# /usr/bin/lftpget -c
# /usr/bin/wget

#-- The package required by makepkg to download VCS sources
#  Format: 'protocol::package'
VCSCLIENTS=('bzr::bzr'
            'git::git'
            'hg::mercurial'
            'svn::subversion')

#-- Using git am to apply patches has benefits, but also downsides
#   one being that people without their .gitconfig set get prompts
#   and the other being that the sha1s vary each time, so fix them
GIT_COMMITTER_NAME="makepkg"
GIT_COMMITTER_EMAIL="makepkg@jetbrains.com"

gitam_mkpkg() {
  git am --committer-date-is-author-date "$@"
}

#########################################################################
# INSTALLATION PREFIX
#########################################################################
#


#-- Compiler and Linker Flags
# -march (or -mcpu) builds exclusively for an architecture
# -mtune optimizes for an architecture, but builds for whole processor family
CPPFLAGS="-D_FORTIFY_SOURCE=2"
CFLAGS="-march=armv8-a -mtune=generic -O2 -pipe -fstack-protector-strong"
CXXFLAGS="${CFLAGS}"
LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro"
# Uncomment to enable hardening (ASLR, High entropy ASLR, DEP)
#LDFLAGS="-pipe -Wl,--dynamicbase,--high-entropy-va,--nxcompat"
#-- Make Flags: change this for DistCC/SMP systems
# The Make job server doesn't work under fakeroot for some reason.
if [[ -z ${FAKEROOTKEY-} ]]; then
  MAKEFLAGS="-j$(($(nproc)+1))"
else
  MAKEFLAGS=""
fi

#-- Debugging flags
DEBUG_CFLAGS="-ggdb -fvar-tracking-assignments"
DEBUG_CXXFLAGS="-ggdb -fvar-tracking-assignments"

#########################################################################
# BUILD ENVIRONMENT
#########################################################################
#
# Defaults: BUILDENV=(fakeroot !distcc color !ccache check !sign)
#  A negated environment option will do the opposite of the comments below.
#
#-- distcc:   Use the Distributed C/C++/ObjC compiler
#-- color:    Colorize output messages
#-- ccache:   Use ccache to cache compilation
#-- check:    Run the check() function if present in the PKGBUILD
#-- sign:     Generate PGP signature file
#
BUILDENV=(!distcc color !ccache check !sign)
#
#-- If using DistCC, your MAKEFLAGS will also need modification. In addition,
#-- specify a space-delimited list of hosts running in the DistCC cluster.
#DISTCC_HOSTS=""
#
#-- Specify a directory for package building.
#BUILDDIR=/tmp/makepkg

#########################################################################
# GLOBAL PACKAGE OPTIONS
#   These are default values for the options=() settings
#########################################################################
#
# Default: OPTIONS=(strip docs !libtool staticlibs emptydirs zipman purge !upx !debug)
#  A negated option will do the opposite of the comments below.
#
#-- strip:      Strip symbols from binaries/libraries
#-- docs:       Save doc directories specified by DOC_DIRS
#-- libtool:    Leave libtool (.la) files in packages
#-- staticlibs: Leave static library (.a) files in packages
#-- emptydirs:  Leave empty directories in packages
#-- zipman:     Compress manual (man and info) pages in MAN_DIRS with gzip
#-- purge:      Remove files specified by PURGE_TARGETS
#-- upx:        Compress binary executable files using UPX
#-- debug:      Add debugging flags as specified in DEBUG_* variables
#
OPTIONS=(strip !docs !libtool staticlibs emptydirs zipman purge !upx !debug)

#-- File integrity checks to use. Valid: md5, sha1, sha256, sha384, sha512
INTEGRITY_CHECK=(md5)
#-- Options to be used when stripping binaries. See `man strip' for details.
STRIP_BINARIES="--strip-all"
#-- Options to be used when stripping shared libraries. See `man strip' for details.
STRIP_SHARED="--strip-unneeded"
#-- Options to be used when stripping static libraries. See `man strip' for details.
STRIP_STATIC="--strip-debug"
##-- Manual (man and info) directories to compress (if zipman is specified)
#MAN_DIRS=(${PREFIX#/}{{,/local}{,/share},/opt/*}/{man,info})
##-- Doc directories to remove (if !docs is specified)
#DOC_DIRS=(${PREFIX#/}{,/local}{,/share}/{doc,gtk-doc})
##-- Files to be removed from all packages (if purge is specified)
#PURGE_TARGETS=(${PREFIX#/}{,/share}/info/dir .packlist *.pod)
#
#ACLOCAL_PATH="${PREFIX}/share/aclocal:/usr/share/aclocal"
#PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"

#########################################################################
# PACKAGE OUTPUT
#########################################################################
#
# Default: put built package and cached source in build directory
#
#-- Destination: specify a fixed directory where all packages will be placed
#PKGDEST=/home/packages
#-- Source cache: specify a fixed directory where source files will be cached
#SRCDEST=/home/sources
#-- Source packages: specify a fixed directory where all src packages will be placed
#SRCPKGDEST=/home/srcpackages
#-- Log files: specify a fixed directory where all log files will be placed
#LOGDEST=/home/makepkglogs
# -- Packager: name/email of the person or organization building packages
PACKAGER="Eldar Abusalimov <Eldar.Abusalimov@jetbrains.com>"
#-- Specify a key to use for package signing
#GPGKEY=""

#########################################################################
# COMPRESSION DEFAULTS
#########################################################################
#
COMPRESSGZ=(gzip -c -f -n)
COMPRESSBZ2=(bzip2 -c -f)
COMPRESSXZ=(xz -c -z -T0 -)
COMPRESSLRZ=(lrzip -q)
COMPRESSLZO=(lzop -q)
COMPRESSZ=(compress -c -f)

#########################################################################
# EXTENSION DEFAULTS
#########################################################################
#
# WARNING: Do NOT modify these variables unless you know what you are
#          doing.
#
PKGEXT='.pkg.tar.xz'
SRCEXT='.src.tar.gz'

# vim: set ft=sh ts=2 sw=2 et:
