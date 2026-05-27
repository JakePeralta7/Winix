// Package winconsole provides UTF-8 string output to stdout and stderr.
//
// On a real console handle the output is routed through WriteConsoleW so the
// terminal receives proper UTF-16 (no codepage conversion needed).
// When the handle is a pipe or file, WriteFile sends the raw UTF-8 bytes
// directly, which is correct for tools that are piped or redirected.
package winconsole

import "base:runtime"
import win "core:sys/windows"

// Error classifies write failures returned by this package.
Error :: enum {
    None,
    Write_Failed,
    Encoding_Failed,
}

// Writer wraps a Windows HANDLE and remembers whether it is an interactive
// console so that write_string can pick the correct Win32 call.
Writer :: struct {
    handle:     win.HANDLE,
    is_console: bool,
}

// stdout returns a Writer for the process standard-output handle.
stdout :: proc() -> Writer {
    h := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
    return Writer{handle = h, is_console = is_console_handle(h)}
}

// stderr returns a Writer for the process standard-error handle.
stderr :: proc() -> Writer {
    h := win.GetStdHandle(win.STD_ERROR_HANDLE)
    return Writer{handle = h, is_console = is_console_handle(h)}
}

// write_string writes s to w.
// An empty string is a no-op and always returns (.None).
write_string :: proc(w: Writer, s: string) -> (n: int, err: Error) {
    if len(s) == 0 {
        return 0, .None
    }
    if w.is_console {
        return write_console(w.handle, s)
    }
    return write_pipe(w.handle, s)
}

// write_line writes s followed by "\r\n" to w.
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

// fmt_last_error formats a Win32 error code as a human-readable string using
// FormatMessageW. Returns "unknown error" if the code cannot be resolved.
// The caller owns the returned string.
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
