[[ "$(declare -p source)"  =~ "declare -a" ]] || return 1
[[ "$(declare -p md5sums)" =~ "declare -a" ]] || return 1


source+=('gdb-fix-using-gnu-print.patch'

         # https://sourceware.org/bugzilla/show_bug.cgi?id=21078
         'gdb-7.12-dynamic-libs.patch'

         # Fix gdbserver not printing inferior PID on Windows
         'gdbserver-Output-PID-right-after-create_inferior-call.patch'

         # https://github.com/bminor/binutils-gdb/commit/1ee7b812e778e4fddcfaa5f0be023dfdfb5a4d6e
         'gdbserver-fix-alloc-ipa-circular-dep.patch'

         # Bugzilla #13669: https://sourceware.org/bugzilla/attachment.cgi?id=8993&action=diff
         'CPP-10461-gdb-limit-cp_print_value_fields-recursion.patch')

md5sums+=('7e01e439650c41cf6ea0f76fd7e52880'
          '03531edc3b1348ed384e2d3e7ecc6520'
          '0154631e18d6921c9f3f8fbc1d985c1e'
          '6e4c0a49876ddc999d09db469bfeccd6'
          '5d3c5e700b8cfc3b05e1e20203a1466f')


gdb_enable_targets=(
    'i686-pc-mingw32'

    'i686-linux-gnu'
    'i686-w64-mingw32'
    'x86_64-linux-gnu'
    'x86_64-w64-mingw32'

    'aarch64-linux-gnu'
    'alpha-linux-gnu'
    'arm-linux-gnu'
    'arm-linux-gnueabi'
    'arm-linux-gnueabihf'
    'hppa-linux-gnu'
    'ia64-linux-gnu'
    'm68k-linux-gnu'
    'm68k-rtems'
    'mips-linux-gnu'
    'mipsel-linux-gnu'
    'mips64-linux-gnu'
    'mips64el-linux-gnu'
    'powerpc-linux-gnu'
    'powerpc-linux-gnuspe'
    'powerpc64le-linux-gnu'
    'powerpc64-linux-gnu'
    's390-linux-gnu'
    's390x-linux-gnu'
    'sh-linux-gnu'
    'sparc-linux-gnu'
    'sparc64-linux-gnu'
    'm32r-linux-gnu'
)

