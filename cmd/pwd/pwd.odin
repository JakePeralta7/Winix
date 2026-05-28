// Thin shim: re-exports the path-resolution helpers from internal/winpath
// so that cmd/pwd/main.odin can remain unchanged in structure.
package main

import winpath "../../internal/winpath"

Error             :: winpath.Error
get_cwd_physical  :: winpath.get_cwd_physical
get_cwd_logical   :: winpath.get_cwd_logical
