// package main streams file contents to process stdout using Win32 handles,
// with optional line-oriented transforms (-n/-b/-s/-E/-T/-v).
package main

import "core:strconv"
import win "core:sys/windows"
import "../../internal/winio"

// Cat_Options carries the transforms requested on the command line.
Cat_Options :: struct {
	number:           bool, // -n
	number_nonblank:  bool, // -b (overrides -n)
	squeeze_blank:    bool, // -s
	show_ends:        bool, // -E (also -e = -vE)
	show_tabs:        bool, // -T (also -t = -vT)
	show_nonprinting: bool, // -v
}

// write_file_to_stdout processes path to stdout according to opts.
write_file_to_stdout :: proc(path: string, opts: Cat_Options) -> winio.Error {
	file_handle, err := winio.open_file_for_read(path)
	if err != .None {
		return err
	}
	defer win.CloseHandle(file_handle)
	return stream_handle(file_handle, opts)
}

// write_stdin_to_stdout processes standard input to stdout according to opts.
write_stdin_to_stdout :: proc(opts: Cat_Options) -> winio.Error {
	in_h := win.GetStdHandle(win.STD_INPUT_HANDLE)
	return stream_handle(in_h, opts)
}

// stream_handle copies a handle to stdout, applying opts line transforms.
stream_handle :: proc(h: win.HANDLE, opts: Cat_Options) -> winio.Error {
	out := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	if out == win.INVALID_HANDLE {
		return .Write_Failed
	}

	state := cat_state{
		number =          opts.number || opts.number_nonblank,
		number_nonblank = opts.number_nonblank,
		squeeze_blank =   opts.squeeze_blank,
		show_ends =       opts.show_ends,
		show_tabs =       opts.show_tabs,
		show_nonprinting = opts.show_nonprinting,
	}

	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
	line := make([dynamic]u8, 0, 1024, context.temp_allocator)
	for {
		read: win.DWORD
		if !win.ReadFile(h, rawptr(raw_data(buf)), win.DWORD(len(buf)), &read, nil) {
			return .Read_Failed
		}
		if read == 0 {
			break
		}
		if err := process_bytes(out, &state, &line, buf[:read]); err != .None {
			return err
		}
	}
	if len(line) > 0 {
		if err := emit_line(out, &state, line[:], false); err != .None {
			return err
		}
	}
	return .None
}

// cat_state tracks line count and blank-line suppression state.
cat_state :: struct {
	number:           bool,
	number_nonblank:  bool,
	squeeze_blank:    bool,
	show_ends:        bool,
	show_tabs:        bool,
	show_nonprinting: bool,
	line_num:         int, // next logical line number (1-based)
	blank_seen:       bool, // last emitted line was blank (for -s)
}

// process_bytes ingests a buffer, splitting on '\n' and emitting complete lines.
process_bytes :: proc(out: win.HANDLE, state: ^cat_state, line: ^[dynamic]u8, data: []u8) -> winio.Error {
	for b in data {
		append(line, b)
		if b == '\n' {
			if err := emit_line(out, state, line[:], true); err != .None {
				return err
			}
			clear(line)
		}
	}
	return .None
}

// emit_line writes one complete line (ending in '\n' when terminated=true).
emit_line :: proc(out: win.HANDLE, state: ^cat_state, line: []u8, terminated: bool) -> winio.Error {
	content := line[:len(line)]
	if terminated && len(content) > 0 && content[len(content)-1] == '\n' {
		content = content[:len(content)-1]
	}

	is_blank := len(content) == 0

	if state.squeeze_blank {
		if is_blank && state.blank_seen {
			return .None
		}
		state.blank_seen = is_blank
	}

	if state.number {
		state.line_num += 1
		apply := state.number && (!state.number_nonblank || !is_blank)
		if apply {
			buf: [32]u8
			s := strconv.write_int(buf[:], i64(state.line_num), 10)
			if !wr(out, s) {
				return .Write_Failed
			}
			if !wr(out, "\t") {
				return .Write_Failed
			}
		}
	}

	if len(content) > 0 {
		if err := write_transformed(out, state, content); err != .None {
			return err
		}
	}
	if terminated {
		if state.show_ends {
			if !wr(out, "$") {
				return .Write_Failed
			}
		}
		if !wr(out, "\n") {
			return .Write_Failed
		}
	}
	return .None
}

// write_transformed writes content mapping tabs and control characters.
write_transformed :: proc(out: win.HANDLE, state: ^cat_state, content: []u8) -> winio.Error {
	if !state.show_tabs && !state.show_nonprinting {
		if !winio.write_all(out, content) {
			return .Write_Failed
		}
		return .None
	}
	for i := 0; i < len(content); {
		b := content[i]
		switch {
		case b == '\t' && state.show_tabs:
			if !wr(out, "^I") { return .Write_Failed }
			i += 1
		case b == 0x7F && state.show_nonprinting:
			if !wr(out, "^?") { return .Write_Failed }
			i += 1
		case b < 0x20 && state.show_nonprinting:
			if !winio.write_all(out, []u8{'^', b + 64}) { return .Write_Failed }
			i += 1
		case b >= 0x80:
			n := rune_len(b)
			if i + n > len(content) {
				n = len(content) - i
			}
			if !winio.write_all(out, content[i:i+n]) {
				return .Write_Failed
			}
			i += n
		case:
			if !winio.write_all(out, content[i:i+1]) { return .Write_Failed }
			i += 1
		}
	}
	return .None
}

// rune_len returns the UTF-8 byte length implied by a lead byte.
rune_len :: proc(b: u8) -> int {
	if b < 0x80 { return 1 }
	if b < 0xE0 { return 2 }
	if b < 0xF0 { return 3 }
	return 4
}

// wr writes a single string to an output handle.
wr :: proc(out: win.HANDLE, s: string) -> bool {
	return winio.write_all(out, transmute([]u8)s)
}