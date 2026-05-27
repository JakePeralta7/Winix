// package main moves or renames files and directories using Win32.
//
// move renames src to dst.  When dst is an existing directory, src is placed
// inside it (i.e. dst\basename(src)).  MoveFileExW is used so that cross-
// volume moves (which require a copy+delete) work transparently.
package main

import win "core:sys/windows"
import "../../internal/winio"

// MOVEFILE flags not yet exported by core:sys/windows.
MOVEFILE_REPLACE_EXISTING :: win.DWORD(0x00000001)
MOVEFILE_COPY_ALLOWED     :: win.DWORD(0x00000002)

Error :: enum {
	None,
	Src_Not_Found,
	Access_Denied,
	Move_Failed,
}

// Notify_Proc, when non-nil, is called after each successful move.
Notify_Proc :: #type proc(src, dst: string)

// move moves or renames src to dst.
// When dst is an existing directory, src is moved inside it.
// When no_clobber is true, an existing dst file is not overwritten.
move :: proc(src, dst: string, no_clobber: bool, notify: Notify_Proc = nil) -> Error {
	actual_dst := resolve_dst(src, dst, context.temp_allocator)
	return do_move(src, actual_dst, no_clobber, notify)
}

// resolve_dst returns the effective destination path for a single src→dst move.
// If dst is an existing directory, the result is dst\basename(src).
@(private)
resolve_dst :: proc(src, dst: string, allocator := context.allocator) -> string {
	if winio.is_directory(dst) {
		return winio.join_path(dst, winio.basename(src), allocator)
	}
	return dst
}

@(private)
do_move :: proc(src, dst: string, no_clobber: bool, notify: Notify_Proc) -> Error {
	// Check that src exists.
	wsrc := win.utf8_to_wstring(src, context.temp_allocator)
	if win.GetFileAttributesW(wsrc) == winio.INVALID_FILE_ATTRS {
		ec := win.GetLastError()
		if ec == win.ERROR_FILE_NOT_FOUND || ec == win.ERROR_PATH_NOT_FOUND {
			return .Src_Not_Found
		}
		return .Move_Failed
	}

	// If no-clobber and dst already exists, skip silently.
	wdst := win.utf8_to_wstring(dst, context.temp_allocator)
	if no_clobber && win.GetFileAttributesW(wdst) != winio.INVALID_FILE_ATTRS {
		return .None
	}

	flags := MOVEFILE_COPY_ALLOWED
	if !no_clobber {
		flags |= MOVEFILE_REPLACE_EXISTING
	}

	if !win.MoveFileExW(wsrc, wdst, flags) {
		ec := win.GetLastError()
		switch ec {
		case win.ERROR_FILE_NOT_FOUND, win.ERROR_PATH_NOT_FOUND:
			return .Src_Not_Found
		case win.ERROR_ACCESS_DENIED:
			return .Access_Denied
		}
		return .Move_Failed
	}

	if notify != nil {
		notify(src, dst)
	}
	return .None
}
