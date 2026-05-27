// package main outputs the first N lines of a file to process stdout.
package main

import win "core:sys/windows"
import "../../internal/winio"

// write_head copies the first n lines of path to stdout.
write_head :: proc(path: string, n: int) -> winio.Error {
	fh, err := winio.open_file_for_read(path)
	if err != .None {
		return err
	}
	defer win.CloseHandle(fh)

	out := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	if out == win.INVALID_HANDLE {
		return .Write_Failed
	}

	if n == 0 {
		return .None
	}

	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
	lines_left := n
	for lines_left > 0 {
		read: win.DWORD
		if !win.ReadFile(fh, rawptr(raw_data(buf)), win.DWORD(len(buf)), &read, nil) {
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

// write_head_from_stdin copies the first n lines of standard input to stdout.
write_head_from_stdin :: proc(n: int) -> winio.Error {
	in_h := win.GetStdHandle(win.STD_INPUT_HANDLE)
	out  := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	if out == win.INVALID_HANDLE {
		return .Write_Failed
	}
	if n == 0 {
		return .None
	}
	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
	lines_left := n
	for lines_left > 0 {
		read: win.DWORD
		if !win.ReadFile(in_h, rawptr(raw_data(buf)), win.DWORD(len(buf)), &read, nil) || read == 0 {
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
