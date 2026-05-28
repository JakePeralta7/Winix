// Package winio provides shared low-level Win32 I/O helpers for winix commands.
//
// Keeping these here prevents the same primitives from being re-declared in
// every per-command package (wincat, winhead, wintail, winrm, winmv, …).
package winio

import "core:strings"
import win "core:sys/windows"

// BUF_SIZE is the common streaming buffer size used by I/O commands.
BUF_SIZE :: 64 * 1024

// INVALID_FILE_ATTRS is the sentinel value returned by GetFileAttributesW on failure.
INVALID_FILE_ATTRS :: win.DWORD(0xFFFF_FFFF)

// Error classifies file I/O failures used by streaming commands (cat, head, tail).
Error :: enum {
	None,
	Not_Found,
	Is_Directory,
	Access_Denied,
	Open_Failed,
	Read_Failed,
	Write_Failed,
}

// open_file_for_read opens path for sequential reading.
// On success the caller must CloseHandle the returned handle.
// Returns INVALID_HANDLE and a non-None Error on failure.
open_file_for_read :: proc(path: string) -> (handle: win.HANDLE, err: Error) {
	wpath := win.utf8_to_wstring(path, context.temp_allocator)
	attrs := win.GetFileAttributesW(wpath)
	if attrs == INVALID_FILE_ATTRS {
		ec := win.GetLastError()
		switch ec {
		case win.ERROR_FILE_NOT_FOUND, win.ERROR_PATH_NOT_FOUND:
			return win.INVALID_HANDLE, .Not_Found
		case win.ERROR_ACCESS_DENIED:
			return win.INVALID_HANDLE, .Access_Denied
		}
		return win.INVALID_HANDLE, .Open_Failed
	}
	if attrs & win.FILE_ATTRIBUTE_DIRECTORY != 0 {
		return win.INVALID_HANDLE, .Is_Directory
	}
	fh := win.CreateFileW(
		wpath,
		win.GENERIC_READ,
		win.FILE_SHARE_READ | win.FILE_SHARE_WRITE | win.FILE_SHARE_DELETE,
		nil,
		win.OPEN_EXISTING,
		win.FILE_ATTRIBUTE_NORMAL,
		nil,
	)
	if fh == win.INVALID_HANDLE {
		ec := win.GetLastError()
		switch ec {
		case win.ERROR_FILE_NOT_FOUND, win.ERROR_PATH_NOT_FOUND:
			return win.INVALID_HANDLE, .Not_Found
		case win.ERROR_ACCESS_DENIED:
			return win.INVALID_HANDLE, .Access_Denied
		}
		return win.INVALID_HANDLE, .Open_Failed
	}
	return fh, .None
}

// is_directory returns true when path refers to an existing directory.
is_directory :: proc(path: string) -> bool {
	wpath := win.utf8_to_wstring(path, context.temp_allocator)
	attrs := win.GetFileAttributesW(wpath)
	return attrs != INVALID_FILE_ATTRS && attrs & win.FILE_ATTRIBUTE_DIRECTORY != 0
}

// basename returns the final path component of path (no trailing separator).
basename :: proc(path: string) -> string {
	p := path
	for len(p) > 0 && (p[len(p)-1] == '\\' || p[len(p)-1] == '/') {
		p = p[:len(p)-1]
	}
	for i := len(p) - 1; i >= 0; i -= 1 {
		if p[i] == '\\' || p[i] == '/' {
			return p[i+1:]
		}
	}
	return p
}

// write_all writes all of data to h, retrying on partial writes.
// Returns false if any WriteFile call fails or writes zero bytes.
write_all :: proc(h: win.HANDLE, data: []u8) -> bool {
	remaining := len(data)
	offset := 0
	for remaining > 0 {
		wrote: win.DWORD
		ok := win.WriteFile(h, rawptr(raw_data(data[offset:])), win.DWORD(remaining), &wrote, nil)
		if !ok || wrote == 0 {
			return false
		}
		offset += int(wrote)
		remaining -= int(wrote)
	}
	return true
}

// join_path joins a directory and a filename with a backslash separator.
// If dir already ends with a separator, no extra separator is added.
// The result is allocated with allocator.
join_path :: proc(dir, name: string, allocator := context.allocator) -> string {
	if len(dir) == 0 {
		return strings.clone(name, allocator)
	}
	last := dir[len(dir)-1]
	if last == '\\' || last == '/' {
		return strings.concatenate({dir, name}, allocator)
	}
	return strings.concatenate({dir, "\\", name}, allocator)
}
