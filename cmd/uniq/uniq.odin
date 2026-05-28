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

// eq_maybe_fold compares two lines for equality, optionally ignoring ASCII case.
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
collect_runs :: proc(content: string, ignore_case: bool) -> [dynamic]Line_Run {
	runs := make([dynamic]Line_Run)

	// Gather all lines (slices into content, no per-line allocation).
	line_list := make([dynamic]string, context.temp_allocator)
	rest := content
	for {
		nl := strings.index_byte(rest, '\n')
		if nl < 0 {
			if len(rest) > 0 {
				line := rest
				if len(line) > 0 && line[len(line)-1] == '\r' {
					line = line[:len(line)-1]
				}
				append(&line_list, line)
			}
			break
		}
		line := rest[:nl]
		if len(line) > 0 && line[len(line)-1] == '\r' {
			line = line[:len(line)-1]
		}
		append(&line_list, line)
		rest = rest[nl+1:]
	}

	lines := line_list[:]
	if len(lines) == 0 { return runs }

	cur   := lines[0]
	count := 1
	for i in 1..<len(lines) {
		if eq_maybe_fold(lines[i], cur, ignore_case) {
			count += 1
		} else {
			append(&runs, Line_Run{line = cur, count = count})
			cur   = lines[i]
			count = 1
		}
	}
	append(&runs, Line_Run{line = cur, count = count})

	return runs
}
