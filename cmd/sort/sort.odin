// package main sorts lines of text read from files or stdin.
package main

import "core:slice"
import "core:strconv"
import "core:strings"
import win "core:sys/windows"
import "../../internal/winio"

// MAX_INPUT_BYTES caps in-memory buffering to prevent DoS via unbounded heap growth.
MAX_INPUT_BYTES :: 256 * 1024 * 1024  // 256 MiB

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
		if len(out) + int(read) > MAX_INPUT_BYTES {
			break
		}
		append(&out, ..buf[:read])
	}
	return out[:]
}

// split_to_lines returns substrings of content split at newline boundaries.
// Trailing \r is stripped from each line.
// The returned strings are slices into content — content must remain alive.
split_to_lines :: proc(content: string) -> []string {
	result := make([dynamic]string)
	rest   := content
	for {
		nl := strings.index_byte(rest, '\n')
		if nl < 0 {
			if len(rest) > 0 {
				line := rest
				if len(line) > 0 && line[len(line)-1] == '\r' {
					line = line[:len(line)-1]
				}
				append(&result, line)
			}
			break
		}
		line := rest[:nl]
		if len(line) > 0 && line[len(line)-1] == '\r' {
			line = line[:len(line)-1]
		}
		append(&result, line)
		rest = rest[nl+1:]
	}
	return result[:]
}

// ascii_lower_byte converts an ASCII uppercase byte to its lowercase form.
ascii_lower_byte :: proc(b: u8) -> u8 {
	if b >= 'A' && b <= 'Z' { return b + 32 }
	return b
}

// compare_alpha reports whether a is lexicographically less than b.
compare_alpha :: proc(a, b: string) -> bool { return a < b }

// compare_fold reports whether a is less than b, ignoring ASCII case.
compare_fold :: proc(a, b: string) -> bool {
	n := len(a)
	if len(b) < n { n = len(b) }
	for i in 0..<n {
		ca := ascii_lower_byte(a[i])
		cb := ascii_lower_byte(b[i])
		if ca != cb { return ca < cb }
	}
	return len(a) < len(b)
}

// compare_numeric reports whether a's numeric value is less than b's.
// Non-numeric strings are treated as 0; ties are broken lexicographically.
compare_numeric :: proc(a, b: string) -> bool {
	na, _ := strconv.parse_f64(strings.trim_space(a))
	nb, _ := strconv.parse_f64(strings.trim_space(b))
	if na != nb { return na < nb }
	return a < b
}

// eq_fold reports whether a and b are equal ignoring ASCII case.
eq_fold :: proc(a, b: string) -> bool {
	if len(a) != len(b) { return false }
	for i in 0..<len(a) {
		if ascii_lower_byte(a[i]) != ascii_lower_byte(b[i]) { return false }
	}
	return true
}

// do_sort sorts lines in place and returns the result slice.
// When unique is true the returned slice may be a subslice of lines.
do_sort :: proc(lines: []string, reverse, numeric, fold_case, unique: bool) -> []string {
	if numeric {
		slice.sort_by(lines, compare_numeric)
	} else if fold_case {
		slice.sort_by(lines, compare_fold)
	} else {
		slice.sort_by(lines, compare_alpha)
	}

	if reverse {
		slice.reverse(lines)
	}

	result := lines
	if unique && len(lines) > 1 {
		j := 1
		for i in 1..<len(lines) {
			same: bool
			if fold_case {
				same = eq_fold(lines[i], lines[j-1])
			} else {
				same = lines[i] == lines[j-1]
			}
			if !same {
				lines[j] = lines[i]
				j += 1
			}
		}
		result = lines[:j]
	}
	return result
}
