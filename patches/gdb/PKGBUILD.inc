[[ "$(declare -p source)"  =~ "declare -a" ]] || return 1
[[ "$(declare -p md5sums)" =~ "declare -a" ]] || return 1


source+=('gdb-fix-using-gnu-print.patch'

         # https://sourceware.org/bugzilla/show_bug.cgi?id=21078
         'gdb-7.12-dynamic-libs.patch'

         # Fix gdbserver not printing inferior PID on Windows
         'gdbserver-Output-PID-right-after-create_inferior-call.patch'

         # Bugzilla #13669: https://sourceware.org/bugzilla/attachment.cgi?id=8993&action=diff
         'CPP-10461-gdb-limit-cp_print_value_fields-recursion.patch'

         '0005-W32-Always-check-USERPROFILE-if-HOME-is-not-set.patch')

md5sums+=('b43570a387098fe57681fdb6032ab37c'
          '0094c8e11f4df1a0e78ea7926628223c'
          '886ec40b7e5146d560b9be762208a8b7'
          '241f843c093567e3f04b690a2023c68a'
          '7acec8129b8cc4c0bb8d34cbab27e18d')
