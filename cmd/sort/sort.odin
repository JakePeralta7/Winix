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

// split_to_lines returns substrices of content split at delimiter boundaries.
// Trailing \r is stripped from each line when delimiter is '\n'.
// The returned strings are slices into content — content must remain alive.
split_to_lines :: proc(content: string, delim: u8) -> []string {
	result := make([dynamic]string)
	rest   := content
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
				append(&result, line)
			}
			break
		}
		line := rest[:delim_idx]
		if delim == '\n' && len(line) > 0 && line[len(line)-1] == '\r' {
			line = line[:len(line)-1]
		}
		append(&result, line)
		rest = rest[delim_idx+1:]
	}
	return result[:]
}

// ascii_lower_byte converts an ASCII uppercase byte to its lowercase form.
ascii_lower_byte :: proc(b: u8) -> u8 {
	if b >= 'A' && b <= 'Z' { return b + 32 }
	return b
}

// skip_leading_blanks returns the substring with leading spaces/tabs removed.
skip_leading_blanks :: proc(s: string) -> string {
	i := 0
	for i < len(s) && (s[i] == ' ' || s[i] == '\t') {
		i += 1
	}
	return s[i:]
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

// compare_general_numeric is like compare_numeric but ignores leading blanks first.
compare_general_numeric :: proc(a, b: string) -> bool {
	na, _ := strconv.parse_f64(strings.trim_space(skip_leading_blanks(a)))
	nb, _ := strconv.parse_f64(strings.trim_space(skip_leading_blanks(b)))
	if na != nb { return na < nb }
	return a < b
}

// version compares numbers in GNV ./software-version order: split into digit
// and non-digit runs and compare element-wise. Numbers compare numerically.
version :: proc(a, b: string) -> bool {
	ai := 0
	bi := 0
	for ai < len(a) && bi < len(b) {
		if is_digit(a[ai]) && is_digit(b[bi]) {
			va, na := digit_run(a, ai)
			vb, nb := digit_run(b, bi)
			if va != vb {
				return va < vb
			}
			ai = na
			bi = nb
			continue
		}
		ca := a[ai]
		cb := b[bi]
		if ca != cb {
			return ca < cb
		}
		ai += 1
		bi += 1
	}
	// Shorter string sorts first when one is a prefix of the other.
	return len(a) < len(b)
}

// is_digit reports whether b is an ASCII digit.
is_digit :: proc(b: u8) -> bool { return b >= '0' && b <= '9' }

// digit_run parses the numeric value of the digit run starting at i and
// returns the value and the index one past the run.
digit_run :: proc(s: string, i: int) -> (u64, int) {
	v: u64
	j := i
	for j < len(s) && is_digit(s[j]) {
		v = v * 10 + u64(s[j] - '0')
		j += 1
	}
	return v, j
}

// eq_fold reports whether a and b are equal ignoring ASCII case.
eq_fold :: proc(a, b: string) -> bool {
	if len(a) != len(b) { return false }
	for i in 0..<len(a) {
		if ascii_lower_byte(a[i]) != ascii_lower_byte(b[i]) { return false }
	}
	return true
}

// compare_version_less is the comparator for -V.
compare_version_less :: proc(a, b: string) -> bool { return version(a, b) }

// compare_skipped_alpha is lexical comparison after stripping leading blanks.
compare_skipped_alpha :: proc(a, b: string) -> bool {
	return skip_leading_blanks(a) < skip_leading_blanks(b)
}

// do_sort sorts lines per the given options and returns the result slice.
// Ops flags select one comparator (highest wins): version > general_numeric >
// numeric > fold > alpha; -b prefixes the comparison with blank stripping.
do_sort :: proc(lines: []string, reverse, numeric, fold_case, unique, blanks, general_num, version_sort: bool) -> []string {
	if version_sort {
		slice.sort_by(lines, compare_version_less)
	} else if general_num {
		slice.sort_by(lines, compare_general_numeric)
	} else if numeric {
		slice.sort_by(lines, compare_numeric)
	} else if fold_case {
		slice.sort_by(lines, compare_fold)
	} else if blanks {
		slice.sort_by(lines, compare_skipped_alpha)
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
			} else if blanks {
				same = skip_leading_blanks(lines[i]) == skip_leading_blanks(lines[j-1])
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
