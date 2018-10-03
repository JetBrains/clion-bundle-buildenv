[[ "$(declare -p source)"  =~ "declare -a" ]] || return 1
[[ "$(declare -p md5sums)" =~ "declare -a" ]] || return 1


source+=('gdb-fix-using-gnu-print.patch'

         # https://sourceware.org/bugzilla/show_bug.cgi?id=21078
         'gdb-7.12-dynamic-libs.patch'

         # Fix gdbserver not printing inferior PID on Windows
         'gdbserver-Output-PID-right-after-create_inferior-call.patch'

         # https://sourceware.org/bugzilla/show_bug.cgi?id=15600
         'CPP-10055-py3k-fix-python_run_simple_file-using-deprecated-api.patch'

         # Bugzilla #13669: https://sourceware.org/bugzilla/attachment.cgi?id=8993&action=diff
         'CPP-10461-gdb-limit-cp_print_value_fields-recursion.patch')


md5sums+=('d7112b220466a294aa266bb4d5c06a59'
          'aa9da2a8653357d1849f3a1092110461'
          '28b27b7adff739d6d3dc4581597cdda7'
          'c90fe93130e828fb22fbc3aded9605f0'
          '325bf5b7ad6a1e37a348dda3df0df837')


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

