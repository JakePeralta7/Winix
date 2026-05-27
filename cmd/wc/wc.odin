// package main counts lines, words, and bytes using Win32 file handles.
package main

import win "core:sys/windows"
import "../../internal/winio"

// Counts holds the newline, word, and byte tallies for one input stream.
Counts :: struct {
	lines: i64,
	words: i64,
	bytes: i64,
}

// count_file opens path and counts its lines, words, and bytes.
count_file :: proc(path: string) -> (Counts, winio.Error) {
	fh, err := winio.open_file_for_read(path)
	if err != .None {
		return {}, err
	}
	defer win.CloseHandle(fh)
	return count_handle(fh), .None
}

// count_stdin counts lines, words, and bytes from standard input.
count_stdin :: proc() -> Counts {
	h := win.GetStdHandle(win.STD_INPUT_HANDLE)
	return count_handle(h)
}

// count_handle streams h and tallies lines, words, and bytes.
count_handle :: proc(h: win.HANDLE) -> Counts {
	c: Counts
	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
	in_word := false
	for {
		read: win.DWORD
		if !win.ReadFile(h, rawptr(raw_data(buf)), win.DWORD(len(buf)), &read, nil) || read == 0 {
			break
		}
		c.bytes += i64(read)
		for b in buf[:read] {
			if b == '\n' {
				c.lines += 1
			}
			is_space := b == ' ' || b == '\t' || b == '\n' || b == '\r' || b == '\x0c' || b == '\x0b'
			if in_word {
				if is_space { in_word = false }
			} else {
				if !is_space { in_word = true; c.words += 1 }
			}
		}
	}
	return c
}
