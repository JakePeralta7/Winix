// package main moves or renames files and directories using Win32.
//
// move renames src to dst.  When dst is an existing directory, src is placed
// inside it (i.e. dst\basename(src)).  MoveFileExW is used so that cross-
// volume moves (which require a copy+delete) work transparently.
package main

import "core:strings"
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

// Prompt_Proc, when non-nil, is called with the destination before it is
// overwritten.  It returns true when the move should proceed.
Prompt_Proc :: #type proc(dst: string) -> bool

// Move_Opts controls the behaviour of a single move operation.
Move_Opts :: struct {
	no_clobber:    bool,
	update:        bool, // only move when src is newer than dst
	no_target_dir: bool, // treat dst as a normal file (do not auto-append basename)
	prompt:        Prompt_Proc, // when non-nil, called before overwriting
	notify:        Notify_Proc, // called after each successful move
}

// move moves or renames src to dst.
// When dst is an existing directory, src is moved inside it.
move :: proc(src, dst: string, opts: Move_Opts = {}) -> Error {
	actual_dst := resolve_dst(src, dst, opts.no_target_dir, context.temp_allocator)
	return do_move(src, actual_dst, opts)
}

// resolve_dst returns the effective destination path for a single src→dst move.
// If dst is an existing directory (and -T was not given), the result is
// dst\basename(src).
@(private)
resolve_dst :: proc(src, dst: string, no_target_dir: bool, allocator := context.allocator) -> string {
	if !no_target_dir && winio.is_directory(dst) {
		return winio.join_path(dst, winio.basename(src), allocator)
	}
	return dst
}

@(private)
do_move :: proc(src, dst: string, opts: Move_Opts) -> Error {
	// Check that src exists.
	wsrc := win.utf8_to_wstring(src, context.temp_allocator)
	if win.GetFileAttributesW(wsrc) == winio.INVALID_FILE_ATTRS {
		ec := win.GetLastError()
		if ec == win.ERROR_FILE_NOT_FOUND || ec == win.ERROR_PATH_NOT_FOUND {
			return .Src_Not_Found
		}
		return .Move_Failed
	}

	wdst := win.utf8_to_wstring(dst, context.temp_allocator)

	// With -T, an existing directory destination cannot be overwritten.
	if opts.no_target_dir && winio.is_directory(dst) {
		return .Move_Failed
	}

	// If no-clobber and dst already exists, skip silently.
	if opts.no_clobber && exists(dst) {
		return .None
	}

	// If -u and dst exists and is not older than src, skip.
	if opts.update && dst_exists(dst) {
		if !src_newer(src, dst) {
			return .None
		}
	}

	// Prompt before overwriting an existing destination.
	if opts.prompt != nil && exists(dst) {
		if !opts.prompt(dst) {
			return .None
		}
	}

	flags := MOVEFILE_COPY_ALLOWED
	if !opts.no_clobber {
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

	if opts.notify != nil {
		opts.notify(src, dst)
	}
	return .None
}

// exists reports whether path refers to an existing file or directory.
@(private)
exists :: proc(path: string) -> bool {
	wpath := win.utf8_to_wstring(path, context.temp_allocator)
	return win.GetFileAttributesW(wpath) != winio.INVALID_FILE_ATTRS
}

// dst_exists is an alias kept for readability at the -u check site.
@(private)
dst_exists :: proc(path: string) -> bool {
	return exists(path)
}

// src_newer reports whether the last-write time of a is later than b.
// Uses GetFileAttributesExW to avoid opening handles.
@(private)
src_newer :: proc(a, b: string) -> bool {
	atime, aok := query_lwtime(a)
	btime, bok := query_lwtime(b)
	if !aok && !bok {
		return false
	}
	if !aok {
		return false // a missing: never newer
	}
	if !bok {
		return true // b missing: a counts as newer
	}
	// FILETIME dwHighDateTime/dwLowDateTime form a 64-bit count of
	// 100ns intervals since 1601-01-01.
	return filetime_gt(atime, btime)
}

@(private)
filetime_gt :: proc(a, b: win.FILETIME) -> bool {
	if a.dwHighDateTime != b.dwHighDateTime {
		return a.dwHighDateTime > b.dwHighDateTime
	}
	return a.dwLowDateTime > b.dwLowDateTime
}

// query_lwtime returns the last-write time of path and whether it could be
// queried successfully.
@(private)
query_lwtime :: proc(path: string) -> (time: win.FILETIME, ok: bool) {
	info: win.WIN32_FILE_ATTRIBUTE_DATA
	wpath := win.utf8_to_wstring(path, context.temp_allocator)
	if !win.GetFileAttributesExW(wpath, win.GetFileExInfoStandard, &info) {
		return time, false
	}
	return info.ftLastWriteTime, true
}