[[ "$(declare -p source)"  =~ "declare -a" ]] || return 1
[[ "$(declare -p md5sums)" =~ "declare -a" ]] || return 1


source+=('gdb-fix-using-gnu-print.patch'

         # https://sourceware.org/bugzilla/show_bug.cgi?id=21078
         'gdb-7.12-dynamic-libs.patch'

         # https://sourceware.org/bugzilla/show_bug.cgi?id=15600
         'CPP-10055-py3k-fix-python_run_simple_file-using-deprecated-api.patch'

         # Bugzilla #13669: https://sourceware.org/bugzilla/attachment.cgi?id=8993&action=diff
         'CPP-10461-gdb-limit-cp_print_value_fields-recursion.patch'

         # https://sourceware.org/ml/gdb-patches/2018-02/msg00030.html
         'CPP-7331-MI-Allow-non-raw-varobj-evaluation.patch'

         # https://sourceware.org/ml/gdb-patches/2018-02/msg00077.html
         'CPP-11966-Fix-type-of-values-representing-optimized-out-static-members.patch')


md5sums+=('d7112b220466a294aa266bb4d5c06a59'
          'aa9da2a8653357d1849f3a1092110461'
          'c90fe93130e828fb22fbc3aded9605f0'
          '18f5d49270a9ac18af16c53ccfa302a2'
          '4b577626e1716dedf85dccae46376d07'
          '0f80599eaa6d0a9495ce754a1999f6db')


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

