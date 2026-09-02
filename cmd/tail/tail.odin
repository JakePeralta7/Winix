// package main outputs the last N lines or bytes of a file to process stdout.
//
// Lines use a configurable delimiter ('\n' normally, '\x00' with -z).
// Bytes mode takes the last N bytes. The file is scanned backwards via
// SetFilePointerEx; a trailing newline at EOF is not counted as a line.
package main

import win "core:sys/windows"
import "../../internal/winio"

// Tail_Options carries the count selection and mode for tail.
Tail_Options :: struct {
	lines: int, // max lines (-1 = unset → default 10)
	bytes: i64, // max bytes (-1 = unset)
	delim: u8,  // line delimiter ('\n' or 0 for -z)
	follow: bool, // -f: keep reading appended data
}

// write_tail copies the requested tail of path to stdout.
write_tail :: proc(path: string, opts: Tail_Options) -> winio.Error {
	fh, err := winio.open_file_for_read(path)
	if err != .None {
		return err
	}
	defer win.CloseHandle(fh)

	out := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	if out == win.INVALID_HANDLE {
		return .Write_Failed
	}

	file_size: win.LARGE_INTEGER
	if !win.GetFileSizeEx(fh, &file_size) {
		return .Read_Failed
	}
	size := i64(file_size)

	if opts.bytes >= 0 {
		return tail_bytes_h(fh, out, size, opts.bytes)
	}

	n := opts.lines
	if n < 0 {
		n = DEFAULT_LINES
	}
	start, ferr := find_tail_offset_h(fh, size, n, opts.delim)
	if ferr != .None {
		return ferr
	}
	if !win.SetFilePointerEx(fh, win.LARGE_INTEGER(start), nil, win.FILE_BEGIN) {
		return .Read_Failed
	}

	if err := stream_forward(fh, out); err != .None {
		return err
	}

	if opts.follow {
		return follow_file(fh, out, size)
	}
	return .None
}

// write_tail_from_stdin buffers stdin and copies the requested tail to stdout.
write_tail_from_stdin :: proc(opts: Tail_Options) -> winio.Error {
	in_h := win.GetStdHandle(win.STD_INPUT_HANDLE)
	out  := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	if out == win.INVALID_HANDLE {
		return .Write_Failed
	}

	data := make([dynamic]u8)
	defer delete(data)
	tmp: [winio.BUF_SIZE]u8
	for {
		read: win.DWORD
		if !win.ReadFile(in_h, rawptr(&tmp[0]), win.DWORD(len(tmp)), &read, nil) || read == 0 {
			break
		}
		if len(data) + int(read) > MAX_STDIN_BYTES {
			break
		}
		append(&data, ..tmp[:read])
	}

	buf := data[:]
	size := len(buf)
	if size == 0 {
		return .None
	}

	if opts.bytes >= 0 {
		start := 0
		b := opts.bytes
		if i64(size) > b {
			start = int(i64(size) - b)
		}
		if !winio.write_all(out, buf[start:]) {
			return .Write_Failed
		}
		return .None
	}

	n := opts.lines
	if n < 0 {
		n = DEFAULT_LINES
	}
	delim := opts.delim

	start := 0
	newlines := 0
	scan_end := size
	if buf[size-1] == delim {
		scan_end = size - 1
	}
	for i := scan_end - 1; i >= 0; i -= 1 {
		if buf[i] == delim {
			newlines += 1
			if newlines == n {
				start = i + 1
				break
			}
		}
	}
	if !winio.write_all(out, buf[start:]) {
		return .Write_Failed
	}
	return .None
}

// find_tail_offset_h scans backwards and returns the byte offset at which to
// begin reading to output the last n delimited lines.
@(private)
find_tail_offset_h :: proc(fh: win.HANDLE, size: i64, n: int, delim: u8) -> (i64, winio.Error) {
	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
	newlines_found := 0

	scan_end := size
	if size > 0 {
		last_pos := size - 1
		if !win.SetFilePointerEx(fh, win.LARGE_INTEGER(last_pos), nil, win.FILE_BEGIN) {
			return 0, .Read_Failed
		}
		b: [1]u8
		read: win.DWORD
		if !win.ReadFile(fh, rawptr(&b[0]), 1, &read, nil) {
			return 0, .Read_Failed
		}
		if read == 1 && b[0] == delim {
			scan_end = last_pos
		}
	}

	pos := scan_end
	for pos > 0 {
		chunk_start := pos - i64(winio.BUF_SIZE)
		if chunk_start < 0 {
			chunk_start = 0
		}
		chunk_size := pos - chunk_start

		if !win.SetFilePointerEx(fh, win.LARGE_INTEGER(chunk_start), nil, win.FILE_BEGIN) {
			return 0, .Read_Failed
		}
		read: win.DWORD
		if !win.ReadFile(fh, rawptr(raw_data(buf)), win.DWORD(chunk_size), &read, nil) {
			return 0, .Read_Failed
		}

		for i := int(read) - 1; i >= 0; i -= 1 {
			if buf[i] == delim {
				newlines_found += 1
				if newlines_found == n {
					return chunk_start + i64(i) + 1, .None
				}
			}
		}
		pos = chunk_start
	}
	return 0, .None
}

// tail_bytes_h outputs the last b bytes of the file.
@(private)
tail_bytes_h :: proc(fh: win.HANDLE, out: win.HANDLE, size, b: i64) -> winio.Error {
	if size == 0 || b <= 0 {
		return .None
	}
	start := size - b
	if start < 0 {
		start = 0
	}
	if !win.SetFilePointerEx(fh, win.LARGE_INTEGER(start), nil, win.FILE_BEGIN) {
		return .Read_Failed
	}
	return stream_forward(fh, out)
}

// stream_forward copies the remaining bytes of the file to out.
stream_forward :: proc(h: win.HANDLE, out: win.HANDLE) -> winio.Error {
	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
	for {
		read: win.DWORD
		if !win.ReadFile(h, rawptr(raw_data(buf)), win.DWORD(len(buf)), &read, nil) {
			return .Read_Failed
		}
		if read == 0 {
			break
		}
		if !winio.write_all(out, buf[:read]) {
			return .Write_Failed
		}
	}
	return .None
}

// follow_file continuously reads appended data until the stream is closed
// (polls every 250 ms). Initial position is end of current content.
@(private)
follow_file :: proc(fh: win.HANDLE, out: win.HANDLE, start_size: i64) -> winio.Error {
	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
	current := start_size
	for {
		size: win.LARGE_INTEGER
		if win.GetFileSizeEx(fh, &size) {
			if i64(size) > current {
				if !win.SetFilePointerEx(fh, win.LARGE_INTEGER(current), nil, win.FILE_BEGIN) {
					return .Read_Failed
				}
				for {
					read: win.DWORD
					if !win.ReadFile(fh, rawptr(raw_data(buf)), win.DWORD(len(buf)), &read, nil) {
						return .Read_Failed
					}
					if read == 0 {
						break
					}
					if !winio.write_all(out, buf[:read]) {
						return .Write_Failed
					}
				}
				current = i64(size)
			}
		}
		win.Sleep(250)
	}
	return .None
}

MAX_STDIN_BYTES :: 256 * 1024 * 1024 // 256 MiB