// package main implements fixed-string line searching over files and stdin.
package main

import "core:strings"
import win "core:sys/windows"
import "../../internal/winio"

// Match_Opts controls how pattern matching is performed.
Match_Opts :: struct {
	ignore_case: bool, // -i: case-insensitive comparison
	invert:      bool, // -v: select non-matching lines
}

// Line_Match records one matching line.
// The line field is a slice into the source data and is only valid while
// that data buffer is alive.
Line_Match :: struct {
	line_num: int,
	line:     string,
}

// read_all drains h into a heap-allocated byte slice.
// The caller must delete the returned slice.
read_all :: proc(h: win.HANDLE, allocator := context.allocator) -> []u8 {
	out := make([dynamic]u8, 0, winio.BUF_SIZE, allocator)
	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
	for {
		read: win.DWORD
		if !win.ReadFile(h, rawptr(raw_data(buf)), win.DWORD(len(buf)), &read, nil) || read == 0 {
			break
		}
		append(&out, ..buf[:read])
	}
	return out[:]
}

// grep_bytes searches text line-by-line for pattern.
// Line_Match.line fields are slices into text; keep text alive for the
// lifetime of the returned slice.
grep_bytes :: proc(text: string, pattern: string, opts: Match_Opts) -> (results: [dynamic]Line_Match) {
	lpattern := pattern
	if opts.ignore_case {
		lpattern = strings.to_lower(pattern, context.temp_allocator)
	}
	results = make([dynamic]Line_Match)
	rest    := text
	line_num := 1
	for {
		nl   := strings.index_byte(rest, '\n')
		line := rest
		if nl >= 0 {
			line = rest[:nl]
			rest = rest[nl+1:]
		} else {
			rest = ""
		}
		// Strip trailing CR so that CRLF files work correctly.
		if len(line) > 0 && line[len(line)-1] == '\r' {
			line = line[:len(line)-1]
		}
		search_in := line
		if opts.ignore_case {
			search_in = strings.to_lower(line, context.temp_allocator)
		}
		matched := strings.contains(search_in, lpattern)
		if matched != opts.invert {
			append(&results, Line_Match{line_num = line_num, line = line})
		}
		line_num += 1
		if nl < 0 { break }
	}
	return
}

// collect_files appends all regular-file paths found under root to out,
// recursing into sub-directories.  Returned paths are allocated with allocator.
collect_files :: proc(root: string, out: ^[dynamic]string, allocator := context.allocator) {
	pattern  := winio.join_path(root, "*", context.temp_allocator)
	wpattern := win.utf8_to_wstring(pattern, context.temp_allocator)

	fd: win.WIN32_FIND_DATAW
	h := win.FindFirstFileW(wpattern, &fd)
	if h == win.INVALID_HANDLE {
		return
	}
	defer win.FindClose(h)

	for {
		nlen := 0
		for i in 0..<win.MAX_PATH {
			if fd.cFileName[i] == 0 { nlen = i; break }
		}
		name, nerr := win.utf16_to_utf8(fd.cFileName[:nlen], context.temp_allocator)
		if nerr == nil && name != "." && name != ".." {
			full := winio.join_path(root, name, allocator)
			if fd.dwFileAttributes & win.FILE_ATTRIBUTE_DIRECTORY != 0 {
				collect_files(full, out, allocator)
				delete(full, allocator)
			} else {
				append(out, full)
			}
		}
		if !win.FindNextFileW(h, &fd) { break }
	}
}
