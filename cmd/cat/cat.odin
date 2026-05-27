// package main streams file contents to process stdout using Win32 handles.
package main

import win "core:sys/windows"
import "../../internal/winio"

// write_file_to_stdout copies path to stdout without loading the whole file in memory.
write_file_to_stdout :: proc(path: string) -> winio.Error {
	file_handle, err := winio.open_file_for_read(path)
	if err != .None {
		return err
	}
	defer win.CloseHandle(file_handle)

	out := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	if out == win.INVALID_HANDLE {
		return .Write_Failed
	}

	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
	for {
		read: win.DWORD
		if !win.ReadFile(file_handle, rawptr(raw_data(buf)), win.DWORD(len(buf)), &read, nil) {
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

// write_stdin_to_stdout copies standard input to standard output until EOF.
write_stdin_to_stdout :: proc() -> winio.Error {
	in_h := win.GetStdHandle(win.STD_INPUT_HANDLE)
	out  := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	if out == win.INVALID_HANDLE {
		return .Write_Failed
	}
	buf := make([]u8, winio.BUF_SIZE, context.temp_allocator)
	for {
		read: win.DWORD
		if !win.ReadFile(in_h, rawptr(raw_data(buf)), win.DWORD(len(buf)), &read, nil) || read == 0 {
			break
		}
		if !winio.write_all(out, buf[:read]) {
			return .Write_Failed
		}
	}
	return .None
}
