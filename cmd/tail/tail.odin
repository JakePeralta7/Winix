// package main outputs the last N lines of a file to process stdout.
//
// The implementation scans the file backwards in chunks using SetFilePointerEx
// to locate the start of the last n lines, then streams forward to stdout.
// A trailing newline at end-of-file is not counted as an empty line.
package main

import win "core:sys/windows"
import "../../internal/winio"

// write_tail copies the last n lines of path to stdout.
write_tail :: proc(path: string, n: int) -> winio.Error {
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

	if size == 0 || n == 0 {
		return .None
	}

	start, ferr := find_tail_offset(fh, size, n)
	if ferr != .None {
		return ferr
	}

	// Seek to the start of the tail region.
	if !win.SetFilePointerEx(fh, win.LARGE_INTEGER(start), nil, win.FILE_BEGIN) {
		return .Read_Failed
	}

	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
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

	return .None
}

// find_tail_offset scans backwards through the file and returns the byte
// offset at which to begin reading in order to output the last n lines.
// A single trailing newline at EOF is not counted as a line boundary.
@(private)
find_tail_offset :: proc(fh: win.HANDLE, size: i64, n: int) -> (offset: i64, err: winio.Error) {
	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
	newlines_found := 0

	// Check whether the file ends with a newline; if so, skip it.
	scan_end := size
	{
		last_pos := size - 1
		if !win.SetFilePointerEx(fh, win.LARGE_INTEGER(last_pos), nil, win.FILE_BEGIN) {
			return 0, .Read_Failed
		}
		b: [1]u8
		read: win.DWORD
		if !win.ReadFile(fh, rawptr(&b[0]), 1, &read, nil) {
			return 0, .Read_Failed
		}
		if read == 1 && b[0] == '\n' {
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
			if buf[i] == '\n' {
				newlines_found += 1
				if newlines_found == n {
					return chunk_start + i64(i) + 1, .None
				}
			}
		}

		pos = chunk_start
	}

	// Fewer than n lines in the file; return start of file.
	return 0, .None
}

// MAX_STDIN_BYTES caps in-memory buffering from stdin to prevent DoS via
// unbounded heap growth from malicious or excessively large piped input.
MAX_STDIN_BYTES :: 256 * 1024 * 1024  // 256 MiB

// write_tail_from_stdin buffers all of standard input and copies the last n
// lines to stdout. Buffering is required because a pipe is not seekable.
write_tail_from_stdin :: proc(n: int) -> winio.Error {
	in_h := win.GetStdHandle(win.STD_INPUT_HANDLE)
	out  := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	if out == win.INVALID_HANDLE {
		return .Write_Failed
	}
	if n == 0 {
		return .None
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

	buf  := data[:]
	size := len(buf)
	if size == 0 {
		return .None
	}

	// Mirror the file-based logic: ignore a trailing newline.
	scan_end := size
	if buf[size-1] == '\n' {
		scan_end = size - 1
	}

	start      := 0
	newlines   := 0
	for i := scan_end - 1; i >= 0; i -= 1 {
		if buf[i] == '\n' {
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
