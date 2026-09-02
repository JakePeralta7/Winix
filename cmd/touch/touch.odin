// package main creates files or updates their timestamps using Win32.
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

touch :: proc(path: string, opts: Touch_Opts) -> Error {
	wpath := win.utf8_to_wstring(path, context.temp_allocator)

	attrs := win.GetFileAttributesW(wpath)
	if attrs != win.DWORD(0xFFFF_FFFF) && attrs & win.FILE_ATTRIBUTE_DIRECTORY != 0 {
		return .Is_Directory
	}

	access_mask := win.GENERIC_WRITE
	if opts.no_create {
		access_mask = win.GENERIC_READ | win.GENERIC_WRITE
	}

	if opts.no_create {
		fh_check := win.CreateFileW(
			wpath,
			win.GENERIC_READ,
			win.FILE_SHARE_READ | win.FILE_SHARE_WRITE | win.FILE_SHARE_DELETE,
			nil,
			win.OPEN_EXISTING,
			win.FILE_ATTRIBUTE_NORMAL,
			nil,
		)
		if fh_check == win.INVALID_HANDLE {
			return .Touch_Failed
		}
		win.CloseHandle(fh_check)
	}

	creation_disposition := win.OPEN_ALWAYS
	if opts.no_create {
		creation_disposition = win.OPEN_EXISTING
	}

	fh := win.CreateFileW(
		wpath,
		access_mask,
		win.FILE_SHARE_READ | win.FILE_SHARE_WRITE | win.FILE_SHARE_DELETE,
		nil,
		creation_disposition,
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

	target_time: win.FILETIME
	if opts.reference_path != "" {
		ref_wpath := win.utf8_to_wstring(opts.reference_path, context.temp_allocator)
		ref_fh := win.CreateFileW(ref_wpath, win.GENERIC_READ, win.FILE_SHARE_READ, nil, win.OPEN_EXISTING, 0, nil)
		if ref_fh == win.INVALID_HANDLE {
			return .Touch_Failed
		}
		atime: win.FILETIME
		mtime: win.FILETIME
		ctime: win.FILETIME
		if !win.GetFileTime(ref_fh, &ctime, &atime, &mtime) {
			win.CloseHandle(ref_fh)
			return .Touch_Failed
		}
		win.CloseHandle(ref_fh)
		if opts.access_only {
			target_time = atime
		} else if opts.modify_only {
			target_time = mtime
		} else {
			target_time = mtime
		}
	} else {
		GetSystemTimeAsFileTime(&target_time)
	}

	atime_ptr: ^win.FILETIME
	mtime_ptr: ^win.FILETIME
	if opts.access_only {
		atime_ptr = &target_time
		mtime_ptr = nil
	} else if opts.modify_only {
		atime_ptr = nil
		mtime_ptr = &target_time
	} else {
		atime_ptr = &target_time
		mtime_ptr = &target_time
	}

	if !SetFileTime(fh, nil, atime_ptr, mtime_ptr) {
		return .Touch_Failed
	}

	return .None
}

Touch_Opts :: struct {
	access_only:     bool,
	modify_only:     bool,
	no_create:       bool,
	reference_path:  string,
}