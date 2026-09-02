// package main outputs the first N lines or bytes of a file to process stdout.
package main

import win "core:sys/windows"
import "../../internal/winio"

// Head_Options carries the count selection for head.
Head_Options :: struct {
	lines: int, // max lines to emit (-1 = unset → default)
	bytes: i64, // max bytes to emit (-1 = unset)
}

// write_head outputs the requested prefix of path to stdout.
write_head :: proc(path: string, opts: Head_Options) -> winio.Error {
	fh, err := winio.open_file_for_read(path)
	if err != .None {
		return err
	}
	defer win.CloseHandle(fh)

	out := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	if out == win.INVALID_HANDLE {
		return .Write_Failed
	}

	if opts.bytes >= 0 {
		return write_head_bytes_h(fh, out, opts.bytes)
	}
	n := opts.lines
	if opts.lines < 0 {
		n = DEFAULT_LINES
	}
	return write_head_lines_h(fh, out, n)
}

// write_head_from_stdin outputs the requested prefix of stdin to stdout.
write_head_from_stdin :: proc(opts: Head_Options) -> winio.Error {
	in_h := win.GetStdHandle(win.STD_INPUT_HANDLE)
	out  := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	if out == win.INVALID_HANDLE {
		return .Write_Failed
	}
	if opts.bytes >= 0 {
		return write_head_bytes_h(in_h, out, opts.bytes)
	}
	n := opts.lines
	if opts.lines < 0 {
		n = DEFAULT_LINES
	}
	return write_head_lines_h(in_h, out, n)
}

// write_head_lines_h falls back to no-op streaming of raw bytes when n is huge,
// but for typical n it copies only the first n lines.
write_head_lines_h :: proc(h: win.HANDLE, out: win.HANDLE, n: int) -> winio.Error {
	if n == 0 {
		return .None
	}
	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
	lines_left := n
	for lines_left > 0 {
		read: win.DWORD
		if !win.ReadFile(h, rawptr(raw_data(buf)), win.DWORD(len(buf)), &read, nil) {
			return .Read_Failed
		}
		if read == 0 {
			break
		}
		chunk := buf[:read]
		write_end := 0
		for i in 0 ..< int(read) {
			write_end = i + 1
			if chunk[i] == '\n' {
				lines_left -= 1
				if lines_left == 0 {
					break
				}
			}
		}
		if !winio.write_all(out, chunk[:write_end]) {
			return .Write_Failed
		}
	}
	return .None
}

// write_head_bytes_h copies exactly b bytes from h to out (or fewer at EOF).
write_head_bytes_h :: proc(h: win.HANDLE, out: win.HANDLE, b: i64) -> winio.Error {
	if b <= 0 {
		return .None
	}
	remaining := b
	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
	for remaining > 0 {
		want := int(remaining)
		if want > len(buf) {
			want = len(buf)
		}
		read: win.DWORD
		if !win.ReadFile(h, rawptr(raw_data(buf)), win.DWORD(want), &read, nil) {
			return .Read_Failed
		}
		if read == 0 {
			break
		}
		if !winio.write_all(out, buf[:read]) {
			return .Write_Failed
		}
		remaining -= i64(read)
	}
	return .None
}