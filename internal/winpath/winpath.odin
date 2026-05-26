package winpath

import "base:runtime"
import "core:strings"
import win "core:sys/windows"

Error :: enum {
    None,
    GetCwd_Failed,
    Env_Read_Failed,
    Open_Failed,
    Resolve_Failed,
    Encoding_Failed,
}

get_cwd_physical :: proc(allocator := context.allocator) -> (path: string, err: Error) {
    raw := read_cwd_utf16(context.temp_allocator) or_return
    h := open_dir_handle(raw)
    if h == win.INVALID_HANDLE {
        return normalize(raw, allocator)
    }
    defer win.CloseHandle(h)
    resolved, rerr := resolve_final(h, context.temp_allocator)
    if rerr != .None {
        return normalize(raw, allocator)
    }
    return normalize(resolved, allocator)
}

get_cwd_logical :: proc(allocator := context.allocator) -> (path: string, err: Error) {
    pwd, perr := read_env_utf16("PWD", context.temp_allocator)
    if perr != .None || len(pwd) == 0 {
        return get_cwd_physical(allocator)
    }
    if !is_absolute_w(pwd) {
        return get_cwd_physical(allocator)
    }
    if !same_dir(pwd) {
        return get_cwd_physical(allocator)
    }
    return normalize(pwd, allocator)
}

@(private)
read_env_utf16 :: proc(name: string, allocator: runtime.Allocator) -> ([]u16, Error) {
    nm := win.utf8_to_wstring(name, context.temp_allocator)
    n := win.GetEnvironmentVariableW(nm, nil, 0)
    if n == 0 {
        return nil, .Env_Read_Failed
    }
    buf := make([]u16, int(n), allocator)
    got := win.GetEnvironmentVariableW(nm, raw_data(buf), n)
    if got == 0 {
        return nil, .Env_Read_Failed
    }
    return buf[:got], .None
}

@(private)
is_absolute_w :: proc(wpath: []u16) -> bool {
    if len(wpath) >= 3 {
        c := wpath[0]
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) &&
           wpath[1] == ':' && wpath[2] == '\\' {
            return true
        }
    }
    if len(wpath) >= 2 && wpath[0] == '\\' && wpath[1] == '\\' {
        return true
    }
    return false
}

@(private)
same_dir :: proc(wpath: []u16) -> bool {
    z := make([]u16, len(wpath)+1, context.temp_allocator)
    copy(z, wpath)
    z[len(wpath)] = 0
    share: win.DWORD = win.FILE_SHARE_READ | win.FILE_SHARE_WRITE | win.FILE_SHARE_DELETE
    h1 := win.CreateFileW(
        win.wstring(raw_data(z)), 0,
        share, nil, win.OPEN_EXISTING, win.FILE_FLAG_BACKUP_SEMANTICS, nil,
    )
    if h1 == win.INVALID_HANDLE do return false
    defer win.CloseHandle(h1)

    raw, rerr := read_cwd_utf16(context.temp_allocator)
    if rerr != .None do return false
    h2 := open_dir_handle(raw)
    if h2 == win.INVALID_HANDLE do return false
    defer win.CloseHandle(h2)

    info1, info2: win.BY_HANDLE_FILE_INFORMATION
    if !win.GetFileInformationByHandle(h1, &info1) do return false
    if !win.GetFileInformationByHandle(h2, &info2) do return false
    return info1.dwVolumeSerialNumber == info2.dwVolumeSerialNumber &&
           info1.nFileIndexHigh       == info2.nFileIndexHigh &&
           info1.nFileIndexLow        == info2.nFileIndexLow
}

@(private)
read_cwd_utf16 :: proc(allocator: runtime.Allocator) -> ([]u16, Error) {
    n := win.GetCurrentDirectoryW(0, nil)
    if n == 0 {
        return nil, .GetCwd_Failed
    }
    buf := make([]u16, int(n), allocator)
    got := win.GetCurrentDirectoryW(n, raw_data(buf))
    if got == 0 || got >= n {
        return nil, .GetCwd_Failed
    }
    return buf[:got], .None
}

@(private)
open_dir_handle :: proc(wpath: []u16) -> win.HANDLE {
    z := make([]u16, len(wpath)+1, context.temp_allocator)
    copy(z, wpath)
    z[len(wpath)] = 0
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

@(private)
resolve_final :: proc(h: win.HANDLE, allocator: runtime.Allocator) -> ([]u16, Error) {
    n := win.GetFinalPathNameByHandleW(h, nil, 0, 0)
    if n == 0 {
        return nil, .Resolve_Failed
    }
    buf := make([]u16, int(n), allocator)
    got := win.GetFinalPathNameByHandleW(h, win.wstring(raw_data(buf)), n, 0)
    if got == 0 || got >= n {
        return nil, .Resolve_Failed
    }
    return buf[:got], .None
}

@(private)
normalize :: proc(wpath: []u16, allocator: runtime.Allocator) -> (string, Error) {
    s8, _ := win.utf16_to_utf8(wpath, context.temp_allocator)
    if len(s8) == 0 && len(wpath) != 0 {
        return "", .Encoding_Failed
    }
    s8 = strip_extended_prefix(s8)
    s8 = upper_drive_letter(s8)
    s8 = trim_trailing_backslash(s8)
    return strings.clone(s8, allocator), .None
}

@(private)
strip_extended_prefix :: proc(s: string) -> string {
    if strings.has_prefix(s, "\\\\?\\UNC\\") {
        return strings.concatenate({"\\\\", s[len("\\\\?\\UNC\\"):]}, context.temp_allocator)
    }
    if strings.has_prefix(s, "\\\\?\\") {
        return s[len("\\\\?\\"):]
    }
    return s
}

@(private)
upper_drive_letter :: proc(s: string) -> string {
    if len(s) >= 2 && s[1] == ':' && s[0] >= 'a' && s[0] <= 'z' {
        b := make([]u8, len(s), context.temp_allocator)
        copy(b, transmute([]u8)s)
        b[0] = s[0] - 'a' + 'A'
        return string(b)
    }
    return s
}

@(private)
trim_trailing_backslash :: proc(s: string) -> string {
    if len(s) == 3 && s[1] == ':' && s[2] == '\\' {
        return s
    }
    if strings.has_prefix(s, "\\\\") {
        first := strings.index_byte(s[2:], '\\')
        if first >= 0 {
            second := strings.index_byte(s[2+first+1:], '\\')
            if second < 0 || (2+first+1+second) == len(s)-1 {
                if len(s) > 0 && s[len(s)-1] != '\\' {
                    return strings.concatenate({s, "\\"}, context.temp_allocator)
                }
                return s
            }
        }
    }
    out := s
    for len(out) > 0 && out[len(out)-1] == '\\' {
        out = out[:len(out)-1]
    }
    return out
}
