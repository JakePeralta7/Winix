// package main creates files or updates their timestamps using Win32.
//
// touch opens a file with OPEN_ALWAYS (creating it if absent) and then calls
// SetFileTime to set both the last-access and last-write times to the current
// UTC time.  Directories are rejected with Is_Directory.
package main

import win "core:sys/windows"

foreign import kernel32 "system:Kernel32.lib"

@(default_calling_convention = "stdcall")
foreign kernel32 {
	SetFileTime            :: proc(hFile: win.HANDLE, lpCreationTime: ^win.FILETIME, lpLastAccessTime: ^win.FILETIME, lpLastWriteTime: ^win.FILETIME) -> win.BOOL ---
	GetSystemTimeAsFileTime :: proc(lpSystemTimeAsFileTime: ^win.FILETIME) ---
}

Error :: enum {
	None,
	Is_Directory,
	Access_Denied,
	Touch_Failed,
}

// touch creates path if it does not exist, otherwise updates its timestamps.
touch :: proc(path: string) -> Error {
	wpath := win.utf8_to_wstring(path, context.temp_allocator)

	// Reject directories before attempting to open.
	attrs := win.GetFileAttributesW(wpath)
	if attrs != win.DWORD(0xFFFF_FFFF) && attrs & win.FILE_ATTRIBUTE_DIRECTORY != 0 {
		return .Is_Directory
	}

	fh := win.CreateFileW(
		wpath,
		win.GENERIC_WRITE,
		win.FILE_SHARE_READ | win.FILE_SHARE_WRITE | win.FILE_SHARE_DELETE,
		nil,
		win.OPEN_ALWAYS,
		win.FILE_ATTRIBUTE_NORMAL,
		nil,
	)
	if fh == win.INVALID_HANDLE {
		ec := win.GetLastError()
		if ec == win.ERROR_ACCESS_DENIED {
			return .Access_Denied
		}
		return .Touch_Failed
	}
	defer win.CloseHandle(fh)

	now: win.FILETIME
	GetSystemTimeAsFileTime(&now)
	if !SetFileTime(fh, nil, &now, &now) {
		return .Touch_Failed
	}

	return .None
}
