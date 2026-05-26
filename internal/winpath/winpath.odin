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

@(private)
read_cwd_utf16 :: proc(allocator: runtime.Allocator) -> ([]u16, Error) {
    n := win.GetCurrentDirectoryW(0, nil)
    if n == 0 {
        return nil, .GetCwd_Failed
    }
    buf := make([]u16, int(n), allocator)
    got := win.GetCurrentDirectoryW(n, raw_data(buf))
    if got == 0 {
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
