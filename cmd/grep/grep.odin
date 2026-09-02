// package main implements regular expression and fixed-string line searching.
package main

import "core:strings"
import regexp "core:text/regex"
import win "core:sys/windows"
import "../../internal/winio"

// Match_Opts controls how pattern matching is performed.
Match_Opts :: struct {
	pattern:     string,              // The pattern string
	ignore_case: bool,                // -i: case-insensitive comparison
	invert:      bool,                // -v: select non-matching lines
	fixed:       bool,                // -F: fixed string, not regex
	regex:       regexp.Regular_Expression,  // compiled regex (only if not fixed)
}

// Line_Match records one matching line.
// The line field is a slice into the source data and is only valid while
// that data buffer is alive.
Line_Match :: struct {
	line_num: int,
	line:     string,
}

// MAX_INPUT_BYTES caps in-memory buffering to prevent DoS via unbounded heap growth.
MAX_INPUT_BYTES :: 256 * 1024 * 1024  // 256 MiB

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
		if len(out) + int(read) > MAX_INPUT_BYTES {
			break
		}
		append(&out, ..buf[:read])
	}
	return out[:]
}

// ascii_lower_byte converts an ASCII uppercase byte to its lowercase form.
ascii_lower_byte :: proc(b: u8) -> u8 {
	if b >= 'A' && b <= 'Z' { return b + 32 }
	return b
}

// string_lower_ascii converts ASCII uppercase chars in s to lowercase.
string_lower_ascii :: proc(s: string, allocator := context.allocator) -> string {
	buf := make([]u8, len(s), allocator)
	for i := 0; i < len(s); i += 1 {
		buf[i] = ascii_lower_byte(s[i])
	}
	return string(buf)
}

// line_matches checks if a line matches the pattern per opts.
line_matches :: proc(line: string, opts: Match_Opts) -> bool {
	if opts.fixed {
		// Fixed string search.
		search_line := line
		search_pattern := opts.pattern
		if opts.ignore_case {
			search_line = string_lower_ascii(line, context.temp_allocator)
			search_pattern = string_lower_ascii(opts.pattern, context.temp_allocator)
		}
		return strings.contains(search_line, search_pattern)
	}
	// Regex search.
	if opts.ignore_case {
		// For case-insensitive regex, use the regex with Case_Insensitive flag.
		// We need to recompile with the flag, or convert both to lowercase.
		// For simplicity, convert line to lowercase.
		lower := string_lower_ascii(line, context.temp_allocator)
		capture, matched := regexp.match_and_allocate_capture(opts.regex, lower)
		defer regexp.destroy_capture(capture)
		return matched
	}
	capture, matched := regexp.match_and_allocate_capture(opts.regex, line)
	defer regexp.destroy_capture(capture)
	return matched
}

// grep_bytes searches text line-by-line for pattern.
// Line_Match.line fields are slices into text; keep text alive for the
// lifetime of the returned slice.
grep_bytes :: proc(text: string, opts: Match_Opts) -> (results: [dynamic]Line_Match) {
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
		matched := line_matches(line, opts)
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