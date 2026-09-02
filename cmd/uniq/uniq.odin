// package main filters adjacent matching lines from a file or stdin.
package main

import "core:strings"
import win "core:sys/windows"
import "../../internal/winio"

// Line_Run records one contiguous run of equal adjacent lines.
Line_Run :: struct {
	line:  string,
	count: int,
}

// read_all drains h into a heap-allocated byte slice.
// The caller must delete the returned slice.
read_all :: proc(h: win.HANDLE) -> []u8 {
	out := make([dynamic]u8, 0, winio.BUF_SIZE)
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

// ascii_lower_byte converts an ASCII uppercase byte to its lowercase form.
ascii_lower_byte :: proc(b: u8) -> u8 {
	if b >= 'A' && b <= 'Z' { return b + 32 }
	return b
}

// skip_to_field skips the first N whitespace-separated fields in s.
skip_to_field :: proc(s: string, n: int) -> string {
	result := s
	for _ in 0..<n {
		// Skip any leading whitespace.
		for len(result) > 0 && (result[0] == ' ' || result[0] == '\t') {
			result = result[1:]
		}
		// Skip the field itself.
		for len(result) > 0 && result[0] != ' ' && result[0] != '\t' {
			result = result[1:]
		}
	}
	// Skip any leading whitespace after skipping fields.
	for len(result) > 0 && (result[0] == ' ' || result[0] == '\t') {
		result = result[1:]
	}
	return result
}

// extract_compare_part extracts the portion of line to be compared.
// It skips N fields (if skip_fields > 0), then skips M chars (if skip_chars > 0),
// then optionally limits to first N chars (if check_chars >= 0).
extract_compare_part :: proc(line: string, skip_fields, skip_chars, check_chars: int) -> string {
	result := line
	if skip_fields > 0 {
		result = skip_to_field(result, skip_fields)
	}
	if skip_chars > 0 {
		if skip_chars >= len(result) {
			return ""
		}
		result = result[skip_chars:]
	}
	if check_chars >= 0 {
		if check_chars > len(result) {
			return result
		}
		result = result[:check_chars]
	}
	return result
}

// eq_maybe_fold compares two compare-parts for equality, optionally ignoring ASCII case.
eq_maybe_fold :: proc(a, b: string, ignore_case: bool) -> bool {
	if !ignore_case { return a == b }
	if len(a) != len(b) { return false }
	for i in 0..<len(a) {
		if ascii_lower_byte(a[i]) != ascii_lower_byte(b[i]) { return false }
	}
	return true
}

// collect_runs groups adjacent equal lines into runs.
// The Line_Run.line strings are slices into content; content must remain alive.
collect_runs :: proc(content: string, ignore_case: bool, skip_fields, skip_chars, check_chars: int, delim: u8) -> [dynamic]Line_Run {
	runs := make([dynamic]Line_Run)

	// Gather all lines (slices into content, no per-line allocation).
	line_list := make([dynamic]string, context.temp_allocator)
	rest := content
	for {
		delim_idx: int
		if delim == 0 {
			delim_idx = strings.index_byte(rest, 0)
		} else {
			delim_idx = strings.index_byte(rest, delim)
		}
		if delim_idx < 0 {
			if len(rest) > 0 {
				line := rest
				if delim == '\n' && len(line) > 0 && line[len(line)-1] == '\r' {
					line = line[:len(line)-1]
				}
				append(&line_list, line)
			}
			break
		}
		line := rest[:delim_idx]
		if delim == '\n' && len(line) > 0 && line[len(line)-1] == '\r' {
			line = line[:len(line)-1]
		}
		append(&line_list, line)
		rest = rest[delim_idx+1:]
	}

	lines := line_list[:]
	if len(lines) == 0 { return runs }

	cur   := lines[0]
	cur_cmp := extract_compare_part(cur, skip_fields, skip_chars, check_chars)
	count := 1
	for i in 1..<len(lines) {
		next_cmp := extract_compare_part(lines[i], skip_fields, skip_chars, check_chars)
		if eq_maybe_fold(next_cmp, cur_cmp, ignore_case) {
			count += 1
		} else {
			append(&runs, Line_Run{line = cur, count = count})
			cur     = lines[i]
			cur_cmp = next_cmp
			count   = 1
		}
	}
	append(&runs, Line_Run{line = cur, count = count})

	return runs
}
