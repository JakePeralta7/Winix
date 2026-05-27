package pwd_integration_test

import "core:os"
import "core:strings"
import "core:testing"
import win "core:sys/windows"

@(private="file")
EXE :: "bin/pwd.exe"

@(private="file")
run :: proc(t: ^testing.T, args: []string, cwd: string) -> (stdout: []byte, stderr: []byte, code: int) {
    full := make([]string, 1 + len(args), context.temp_allocator)
    full[0] = EXE
    for a, i in args {
        full[1+i] = a
    }
    desc := os.Process_Desc{
        command     = full,
        working_dir = cwd,
    }
    state, out, errb, err := os.process_exec(desc, context.allocator)
    if err != nil {
        testing.fail_now(t, "process_exec failed")
    }
    return out, errb, state.exit_code
}

@(private="file")
normalize_path_for_compare :: proc(path: string) -> string {
    out := path
    if strings.has_prefix(out, "\\\\?\\UNC\\") {
        out = strings.concatenate({"\\\\", out[len("\\\\?\\UNC\\"): ]}, context.temp_allocator)
    } else if strings.has_prefix(out, "\\\\?\\") {
        out = out[len("\\\\?\\"):]
    }

    b := make([]u8, len(out), context.temp_allocator)
    copy(b, transmute([]u8)out)
    for i in 0..<len(b) {
        if b[i] == '/' {
            b[i] = '\\'
        }
    }
    out = string(b)

    for len(out) > 0 && out[len(out)-1] == '\\' {
        if len(out) == 3 && out[1] == ':' && out[2] == '\\' {
            break
        }
        out = out[:len(out)-1]
    }
    return out
}

@(private="file")
open_dir_handle :: proc(path: string) -> win.HANDLE {
    w := win.utf8_to_utf16(path, context.temp_allocator)
    z := make([]u16, len(w)+1, context.temp_allocator)
    copy(z, w)
    z[len(w)] = 0

    share: win.DWORD = win.FILE_SHARE_READ | win.FILE_SHARE_WRITE | win.FILE_SHARE_DELETE
    return win.CreateFileW(
        win.wstring(raw_data(z)),
        0,
        share,
        nil,
        win.OPEN_EXISTING,
        win.FILE_FLAG_BACKUP_SEMANTICS,
        nil,
    )
}

@(private="file")
same_directory :: proc(a: string, b: string) -> bool {
    h1 := open_dir_handle(a)
    if h1 == win.INVALID_HANDLE do return false
    defer win.CloseHandle(h1)

    h2 := open_dir_handle(b)
    if h2 == win.INVALID_HANDLE do return false
    defer win.CloseHandle(h2)

    i1, i2: win.BY_HANDLE_FILE_INFORMATION
    if !win.GetFileInformationByHandle(h1, &i1) do return false
    if !win.GetFileInformationByHandle(h2, &i2) do return false

    return i1.dwVolumeSerialNumber == i2.dwVolumeSerialNumber &&
           i1.nFileIndexHigh       == i2.nFileIndexHigh &&
           i1.nFileIndexLow        == i2.nFileIndexLow
}

@(test)
prints_cwd_with_crlf :: proc(t: ^testing.T) {
    tmp_base, _ := os.temp_dir(context.allocator)
    defer delete(tmp_base)
    tmp := strings.trim_suffix(tmp_base, "\\")
    out, _, code := run(t, []string{}, tmp)
    testing.expect_value(t, code, 0)
    line := string(out)
    testing.expect(t, strings.has_suffix(line, "\r\n"), "expected CRLF terminator")
    trimmed := strings.trim_suffix(line, "\r\n")
    actual := normalize_path_for_compare(trimmed)
    expected := normalize_path_for_compare(tmp)
    same_text := strings.equal_fold(actual, expected)
    same_dir := same_directory(actual, expected)
    testing.expect(t, same_text || same_dir, "stdout did not match cwd")
}

@(test)
help_prints_usage_exit_0 :: proc(t: ^testing.T) {
    tmp_base, _ := os.temp_dir(context.allocator)
    defer delete(tmp_base)
    tmp := strings.trim_suffix(tmp_base, "\\")
    out, _, code := run(t, []string{"--help"}, tmp)
    testing.expect_value(t, code, 0)
    testing.expect(t, strings.contains(string(out), "Usage:"), "expected 'Usage:' in help output")
}

@(test)
version_prints_string_exit_0 :: proc(t: ^testing.T) {
    tmp_base, _ := os.temp_dir(context.allocator)
    defer delete(tmp_base)
    tmp := strings.trim_suffix(tmp_base, "\\")
    out, _, code := run(t, []string{"--version"}, tmp)
    testing.expect_value(t, code, 0)
    testing.expect(t, strings.has_prefix(string(out), "pwd (winix) "), "expected 'pwd (winix) ...' prefix")
}

@(test)
unknown_flag_exits_2_with_stderr :: proc(t: ^testing.T) {
    tmp_base, _ := os.temp_dir(context.allocator)
    defer delete(tmp_base)
    tmp := strings.trim_suffix(tmp_base, "\\")
    _, errb, code := run(t, []string{"-X"}, tmp)
    testing.expect_value(t, code, 2)
    testing.expect(t, strings.contains(string(errb), "unknown option"), "expected 'unknown option' on stderr")
}

@(test)
extra_arg_exits_2 :: proc(t: ^testing.T) {
    tmp_base, _ := os.temp_dir(context.allocator)
    defer delete(tmp_base)
    tmp := strings.trim_suffix(tmp_base, "\\")
    _, _, code := run(t, []string{"foo"}, tmp)
    testing.expect_value(t, code, 2)
}

@(test)
hebrew_cwd_is_utf8_in_pipe :: proc(t: ^testing.T) {
    base, _ := os.temp_dir(context.allocator)
    defer delete(base)
    name := "winix-it-שלום"
    dir := strings.concatenate({strings.trim_suffix(base, "\\"), "\\", name}, context.allocator)
    defer delete(dir)
    if !os.exists(dir) {
        if err := os.make_directory(dir); err != nil {
            testing.fail_now(t, "make_directory failed")
        }
    }
    defer os.remove(dir)

    out, _, code := run(t, []string{}, dir)
    testing.expect_value(t, code, 0)
    hebrew_utf8 := "\xD7\xA9\xD7\x9C\xD7\x95\xD7\x9D"
    testing.expect(t, strings.contains(string(out), hebrew_utf8), "expected Hebrew UTF-8 bytes in piped stdout")
}
