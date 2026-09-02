// package main enumerates directory contents using the Win32 Find API.
//
// list_dir returns a slice of Entry values, one per item found.
// Callers must release the slice with free_entries when done.
package main

import win "core:sys/windows"
import "../../internal/winio"

foreign import kernel32 "system:Kernel32.lib"

@(default_calling_convention = "stdcall")
foreign kernel32 {
	FileTimeToLocalFileTime :: proc(lpFileTime: ^win.FILETIME, lpLocalFileTime: ^win.FILETIME) -> win.BOOL ---
}

// Error classifies failures returned by list_dir.
Error :: enum {
	None,
	Find_Failed,
}

// Entry holds the metadata for one directory item.
Entry :: struct {
	name:        string,
	path:        string, // full path used for recursive descent
	is_dir:      bool,
	is_reparse:  bool,
	is_hidden:   bool,
	is_readonly: bool,
	size:        u64,
	year:        u16,
	month:       u16,
	day:         u16,
	hour:        u16,
	minute:      u16,
}

// list_dir enumerates path and returns one Entry per item.
// When all is false, hidden files and . / .. are omitted.
// The caller must free the result with free_entries.
list_dir :: proc(path: string, all: bool, allocator := context.allocator) -> (entries: []Entry, err: Error) {
	p := path if len(path) > 0 else "."
	pattern := winio.join_path(p, "*", context.temp_allocator)

	wpattern := win.utf8_to_wstring(pattern, context.temp_allocator)

	fd: win.WIN32_FIND_DATAW
	h := win.FindFirstFileW(wpattern, &fd)
	if h == win.INVALID_HANDLE {
		// If the path is not a directory (it may be a plain file), we report it
		// via Find_Failed so the caller can handle a single-file operand.
		return nil, .Find_Failed
	}
	defer win.FindClose(h)

	result := make([dynamic]Entry, 0, 16, allocator)
	for {
		if e, ok := to_entry(p, &fd, all, allocator); ok {
			append(&result, e)
		}
		if !win.FindNextFileW(h, &fd) {
			break
		}
	}

	return result[:], .None
}

// free_entries releases all memory allocated by list_dir.
free_entries :: proc(entries: []Entry, allocator := context.allocator) {
	for e in entries {
		delete(e.name, allocator)
		delete(e.path, allocator)
	}
	delete(entries, allocator)
}

// stat_one returns a single Entry describing a file/directory operand (used
// when a path argument is not a directory). Returns ok=false when the path
// cannot be queried.
stat_one :: proc(path: string, allocator := context.allocator) -> (e: Entry, ok: bool) {
	wpath := win.utf8_to_wstring(path, context.temp_allocator)
	info: win.WIN32_FILE_ATTRIBUTE_DATA
	if !win.GetFileAttributesExW(wpath, win.GetFileExInfoStandard, &info) {
		return {}, false
	}
	attrs := info.dwFileAttributes
	e.name = strings_clone(path, allocator)
	e.path = strings_clone(path, allocator)
	e.is_dir      = (attrs & win.FILE_ATTRIBUTE_DIRECTORY) != 0
	e.is_reparse  = (attrs & win.FILE_ATTRIBUTE_REPARSE_POINT) != 0
	e.is_hidden   = (attrs & win.FILE_ATTRIBUTE_HIDDEN) != 0
	e.is_readonly = (attrs & win.FILE_ATTRIBUTE_READONLY) != 0
	e.size = u64(info.nFileSizeHigh) << 32 | u64(info.nFileSizeLow)

	local_ft: win.FILETIME
	sys: win.SYSTEMTIME
	FileTimeToLocalFileTime(&info.ftLastWriteTime, &local_ft)
	win.FileTimeToSystemTime(&local_ft, &sys)
	e.year, e.month, e.day, e.hour, e.minute = sys.year, sys.month, sys.day, sys.hour, sys.minute
	return e, true
}

@(private)
strings_clone :: proc(s: string, allocator := context.allocator) -> string {
	bytes := make([]u8, len(s), allocator)
	copy(bytes, transmute([]u8)s)
	return string(bytes)
}

@(private)
to_entry :: proc(dir: string, fd: ^win.WIN32_FIND_DATAW, all: bool, allocator := context.allocator) -> (Entry, bool) {
	attrs       := fd.dwFileAttributes
	is_hidden   := (attrs & win.FILE_ATTRIBUTE_HIDDEN) != 0
	is_dir      := (attrs & win.FILE_ATTRIBUTE_DIRECTORY) != 0
	is_reparse  := (attrs & win.FILE_ATTRIBUTE_REPARSE_POINT) != 0
	is_readonly := (attrs & win.FILE_ATTRIBUTE_READONLY) != 0

	// Decode the filename (cFileName is null-terminated [MAX_PATH]WCHAR)
	nlen := 0
	for i in 0..<win.MAX_PATH {
		if fd.cFileName[i] == 0 {
			nlen = i
			break
		}
	}

	name, nerr := win.utf16_to_utf8(fd.cFileName[:nlen], allocator)
	if nerr != nil {
		return {}, false
	}

	if !all && (is_hidden || name == "." || name == "..") {
		delete(name, allocator)
		return {}, false
	}

	full_path := winio.join_path(dir, name, allocator)

	// Convert UTC FILETIME -> local SYSTEMTIME
	local_ft: win.FILETIME
	sys: win.SYSTEMTIME
	FileTimeToLocalFileTime(&fd.ftLastWriteTime, &local_ft)
	win.FileTimeToSystemTime(&local_ft, &sys)

	size := u64(fd.nFileSizeHigh) << 32 | u64(fd.nFileSizeLow)

	return Entry{
		name        = name,
		path        = full_path,
		is_dir      = is_dir,
		is_reparse  = is_reparse,
		is_hidden   = is_hidden,
		is_readonly = is_readonly,
		size        = size,
		year        = sys.year,
		month       = sys.month,
		day         = sys.day,
		hour        = sys.hour,
		minute      = sys.minute,
	}, true
}
