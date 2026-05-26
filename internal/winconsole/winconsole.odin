package winconsole

import "base:runtime"
import win "core:sys/windows"

Error :: enum {
    None,
    Write_Failed,
    Encoding_Failed,
}

Writer :: struct {
    handle:     win.HANDLE,
    is_console: bool,
}

stdout :: proc() -> Writer {
    h := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
    return Writer{handle = h, is_console = is_console_handle(h)}
}

stderr :: proc() -> Writer {
    h := win.GetStdHandle(win.STD_ERROR_HANDLE)
    return Writer{handle = h, is_console = is_console_handle(h)}
}

write_string :: proc(w: Writer, s: string) -> (n: int, err: Error) {
    if len(s) == 0 {
        return 0, .None
    }
    if w.is_console {
        return write_console(w.handle, s)
    }
    return write_pipe(w.handle, s)
}

write_line :: proc(w: Writer, s: string) -> (n: int, err: Error) {
    n1, e1 := write_string(w, s)
    if e1 != .None do return n1, e1
    n2, e2 := write_string(w, "\r\n")
    return n1 + n2, e2
}

@(private)
is_console_handle :: proc(h: win.HANDLE) -> bool {
    return win.GetFileType(h) == win.FILE_TYPE_CHAR
}

@(private)
write_pipe :: proc(h: win.HANDLE, s: string) -> (int, Error) {
    written: win.DWORD
    ok := win.WriteFile(h, raw_data(s), win.DWORD(len(s)), &written, nil)
    if !ok {
        return int(written), .Write_Failed
    }
    return int(written), .None
}

@(private)
write_console :: proc(h: win.HANDLE, s: string) -> (int, Error) {
    wbuf := win.utf8_to_utf16(s, context.temp_allocator)
    if len(wbuf) == 0 && len(s) != 0 {
        return 0, .Encoding_Failed
    }
    written: win.DWORD
    ok := win.WriteConsoleW(h, raw_data(wbuf), win.DWORD(len(wbuf)), &written, nil)
    if !ok {
        return 0, .Write_Failed
    }
    return len(s), .None
}

fmt_last_error :: proc(code: u32, allocator := context.allocator) -> string {
    buf: [512]u16
    flags: win.DWORD = win.FORMAT_MESSAGE_FROM_SYSTEM | win.FORMAT_MESSAGE_IGNORE_INSERTS
    n := win.FormatMessageW(flags, nil, win.DWORD(code), 0, raw_data(buf[:]), win.DWORD(len(buf)), nil)
    if n == 0 {
        return clone_string("unknown error", allocator)
    }
    for n > 0 && (buf[n-1] == '\r' || buf[n-1] == '\n' || buf[n-1] == 0) {
        n -= 1
    }
    s, err := win.utf16_to_utf8(buf[:n], allocator)
    if err != nil {
        return clone_string("unknown error", allocator)
    }
    return s
}

@(private)
clone_string :: proc(s: string, allocator: runtime.Allocator) -> string {
    bytes := make([]u8, len(s), allocator)
    copy(bytes, transmute([]u8)s)
    return string(bytes)
}
