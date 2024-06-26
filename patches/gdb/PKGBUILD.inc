[[ "$(declare -p source)"  =~ "declare -a" ]] || return 1
[[ "$(declare -p md5sums)" =~ "declare -a" ]] || return 1


source+=('gdb-fix-using-gnu-print.patch'

         # https://sourceware.org/bugzilla/show_bug.cgi?id=21078
         'gdb-7.12-dynamic-libs.patch'

         # Fix gdbserver not printing inferior PID on Windows
         'gdbserver-Output-PID-right-after-create_inferior-call.patch'

         # Bugzilla #13669: https://sourceware.org/bugzilla/attachment.cgi?id=8993&action=diff
         'CPP-10461-gdb-limit-cp_print_value_fields-recursion.patch'

         '0005-W32-Always-check-USERPROFILE-if-HOME-is-not-set.patch'

         'perf.patch'

         'fix-31727.patch'

         'CPP-30085.patch')

md5sums+=('b43570a387098fe57681fdb6032ab37c'
          '0094c8e11f4df1a0e78ea7926628223c'
          '05cf28cc032408f88a99b407d6dc3098'
          '241f843c093567e3f04b690a2023c68a'
          '7acec8129b8cc4c0bb8d34cbab27e18d'
          '8e75ee649e945cf2c839ac457efd08e2'
          '7e1154eeb40730c16fcfe256ba43748d'
          '74a6fff5be0d1630f813f25bd7ab6e77')
