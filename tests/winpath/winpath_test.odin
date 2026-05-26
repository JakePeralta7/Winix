package winpath_test

import "core:os"
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

@(test)
logical_with_unset_pwd_matches_physical :: proc(t: ^testing.T) {
    os.unset_env("PWD")
    p_log, err1 := winpath.get_cwd_logical(context.allocator)
    defer delete(p_log)
    p_phy, err2 := winpath.get_cwd_physical(context.allocator)
    defer delete(p_phy)
    testing.expect_value(t, err1, winpath.Error.None)
    testing.expect_value(t, err2, winpath.Error.None)
    testing.expect_value(t, p_log, p_phy)
}

@(test)
logical_with_lowercase_pwd_returns_pwd_value :: proc(t: ^testing.T) {
    p_phy, err1 := winpath.get_cwd_physical(context.allocator)
    defer delete(p_phy)
    testing.expect_value(t, err1, winpath.Error.None)

    if !(len(p_phy) >= 2 && p_phy[1] == ':') {
        testing.fail_now(t, "expected drive-letter path for this test")
    }
    lower := make([]u8, len(p_phy), context.allocator)
    defer delete(lower)
    copy(lower, transmute([]u8)p_phy)
    if lower[0] >= 'A' && lower[0] <= 'Z' do lower[0] = lower[0] - 'A' + 'a'

    os.set_env("PWD", string(lower))
    defer os.unset_env("PWD")

    p_log, err2 := winpath.get_cwd_logical(context.allocator)
    defer delete(p_log)
    testing.expect_value(t, err2, winpath.Error.None)
    testing.expect_value(t, p_log, p_phy)
}

@(test)
logical_with_bogus_pwd_falls_back :: proc(t: ^testing.T) {
    os.set_env("PWD", "Z:\\definitely\\does\\not\\exist\\winix-test")
    defer os.unset_env("PWD")
    p_log, err1 := winpath.get_cwd_logical(context.allocator)
    defer delete(p_log)
    p_phy, err2 := winpath.get_cwd_physical(context.allocator)
    defer delete(p_phy)
    testing.expect_value(t, err1, winpath.Error.None)
    testing.expect_value(t, err2, winpath.Error.None)
    testing.expect_value(t, p_log, p_phy)
}
