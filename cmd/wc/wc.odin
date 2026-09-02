// package main counts lines, words, and bytes using Win32 file handles.
package main

import win "core:sys/windows"
import "../../internal/winio"

// Counts holds the newline, word, byte, char, and max-line tallies for one stream.
Counts :: struct {
	lines: i64,
	words: i64,
	bytes: i64,
	chars: i64,
	max_line: i64,
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

// count_handle streams h and tallies lines, words, bytes, and (for characters)
// counts the number of UTF-8 code points.
count_handle :: proc(h: win.HANDLE) -> Counts {
	c: Counts
	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
	in_word := false
	cur_line := i64(0)
	for {
		read: win.DWORD
		if !win.ReadFile(h, rawptr(raw_data(buf)), win.DWORD(len(buf)), &read, nil) || read == 0 {
			break
		}
		chunk := buf[:read]
		c.bytes += i64(read)
		for b in chunk {
			if b == '\n' {
				c.lines += 1
				if cur_line > c.max_line {
					c.max_line = cur_line
				}
				cur_line = 0
			} else {
				cur_line += 1
			}
			is_space := b == ' ' || b == '\t' || b == '\n' || b == '\r' || b == '\x0c' || b == '\x0b'
			if in_word {
				if is_space { in_word = false }
			} else {
				if !is_space { in_word = true; c.words += 1 }
			}
		}
		// Count UTF-8 code points: one per non-continuation byte.
		for b in chunk {
			if (b & 0xC0) != 0x80 {
				c.chars += 1
			}
		}
	}
	// Handle a final line that had no trailing newline.
	if cur_line > c.max_line {
		c.max_line = cur_line
	}
	return c
}
