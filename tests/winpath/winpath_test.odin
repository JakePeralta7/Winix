package winpath_test

import "core:strings"
import "core:testing"
import "../../internal/winpath"

@(test)
physical_returns_absolute_backslashed_path :: proc(t: ^testing.T) {
    p, err := winpath.get_cwd_physical(context.allocator)
    defer delete(p)
    testing.expect_value(t, err, winpath.Error.None)
    testing.expect(t, len(p) >= 3, "path unexpectedly short")
    is_drive_absolute := len(p) >= 3 && p[1] == ':' && p[2] == '\\' &&
                         p[0] >= 'A' && p[0] <= 'Z'
    is_unc_absolute   := strings.has_prefix(p, "\\\\")
    testing.expect(t, is_drive_absolute || is_unc_absolute, "path is not absolute")
    testing.expect(t, !strings.contains(p, "/"), "expected backslashes only")
}

@(test)
physical_has_no_trailing_backslash_except_root :: proc(t: ^testing.T) {
    p, err := winpath.get_cwd_physical(context.allocator)
    defer delete(p)
    testing.expect_value(t, err, winpath.Error.None)
    is_drive_root := len(p) == 3 && p[1] == ':' && p[2] == '\\'
    if !is_drive_root && len(p) > 0 {
        testing.expect(t, p[len(p)-1] != '\\', "unexpected trailing backslash")
    }
}
