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

md5sums+=('6b485bc8b1025610804fef9e111ade24'
          '225646ec91143b400e54c4a7cba4a674'
          'aaf3a9e88684c8606084c6e8073619ab'
          '7ce3fc34c6800e735c52895c7e1d8372'
          '5772cd1777ab34d588e8676ce873c936')
