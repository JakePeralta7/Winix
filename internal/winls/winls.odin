package winls

import "core:strings"
import win "core:sys/windows"

foreign import kernel32 "system:Kernel32.lib"

@(default_calling_convention = "stdcall")
foreign kernel32 {
	FileTimeToLocalFileTime :: proc(lpFileTime: ^win.FILETIME, lpLocalFileTime: ^win.FILETIME) -> win.BOOL ---
}

Error :: enum {
	None,
	Find_Failed,
}

Entry :: struct {
	name:        string,
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
	last := p[len(p)-1]
	pattern: string
	if last == '\\' || last == '/' {
		pattern = strings.concatenate({p, "*"}, context.temp_allocator)
	} else {
		pattern = strings.concatenate({p, "\\*"}, context.temp_allocator)
	}

	wpattern := win.utf8_to_wstring(pattern, context.temp_allocator)

	fd: win.WIN32_FIND_DATAW
	h := win.FindFirstFileW(wpattern, &fd)
	if h == win.INVALID_HANDLE {
		return nil, .Find_Failed
	}
	defer win.FindClose(h)

	result := make([dynamic]Entry, 0, 16, allocator)
	for {
		if e, ok := to_entry(&fd, all, allocator); ok {
			append(&result, e)
		}
		if !win.FindNextFileW(h, &fd) {
			break
		}
	}

	return result[:], .None
}

free_entries :: proc(entries: []Entry, allocator := context.allocator) {
	for e in entries {
		delete(e.name, allocator)
	}
	delete(entries, allocator)
}

@(private)
to_entry :: proc(fd: ^win.WIN32_FIND_DATAW, all: bool, allocator := context.allocator) -> (Entry, bool) {
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

	// Convert UTC FILETIME -> local SYSTEMTIME
	local_ft: win.FILETIME
	sys: win.SYSTEMTIME
	FileTimeToLocalFileTime(&fd.ftLastWriteTime, &local_ft)
	win.FileTimeToSystemTime(&local_ft, &sys)

	size := u64(fd.nFileSizeHigh) << 32 | u64(fd.nFileSizeLow)

	return Entry{
		name        = name,
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
