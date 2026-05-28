// package main removes files and directory trees using the Win32 API.
//
// remove deletes a single file.
// remove_all deletes a file or recursively empties and removes a directory tree.
// An optional Notify_Proc is called after each successful deletion when the
// caller passes -v / --verbose.
package main

import "base:runtime"
import win "core:sys/windows"
import "../../internal/winio"

Error :: enum {
	None,
	Not_Found,
	Is_Directory,
	Access_Denied,
	Remove_Failed,
}

// Kind describes what a path refers to.
Kind :: enum { File, Directory, Reparse_Dir, Not_Found }

// Notify_Proc, when non-nil, is called after each successful removal.
// is_dir is true when the removed item was a directory.
Notify_Proc :: #type proc(path: string, is_dir: bool)

// stat returns the Kind of path without allocating.
@(private)
stat :: proc(path: string) -> (Kind, Error) {
	wpath := win.utf8_to_wstring(path, context.temp_allocator)
	attrs := win.GetFileAttributesW(wpath)
	if attrs == winio.INVALID_FILE_ATTRS {
		ec := win.GetLastError()
		if ec == win.ERROR_FILE_NOT_FOUND || ec == win.ERROR_PATH_NOT_FOUND {
			return .Not_Found, .None
		}
		return .Not_Found, .Remove_Failed
	}
	// Check reparse point before directory: a directory symlink/junction has both
	// FILE_ATTRIBUTE_DIRECTORY and FILE_ATTRIBUTE_REPARSE_POINT set. We must NOT
	// recurse into it — treat it as an opaque removable object.
	if attrs & win.FILE_ATTRIBUTE_REPARSE_POINT != 0 && attrs & win.FILE_ATTRIBUTE_DIRECTORY != 0 {
		return .Reparse_Dir, .None
	}
	if attrs & win.FILE_ATTRIBUTE_DIRECTORY != 0 {
		return .Directory, .None
	}
	return .File, .None
}

// remove removes a single file.
// Returns .Is_Directory when path refers to a directory.
// Returns .Not_Found when path does not exist.
remove :: proc(path: string, notify: Notify_Proc = nil) -> Error {
	k, kerr := stat(path)
	if kerr != .None { return kerr }
	switch k {
	case .Not_Found:
		return .Not_Found
	case .Directory:
		return .Is_Directory
	case .Reparse_Dir:
		// Directory symlink/junction: remove the link itself without following it.
		wpath := win.utf8_to_wstring(path, context.temp_allocator)
		if !win.RemoveDirectoryW(wpath) {
			return win_err(win.GetLastError())
		}
		if notify != nil { notify(path, true) }
	case .File:
		wpath := win.utf8_to_wstring(path, context.temp_allocator)
		if !win.DeleteFileW(wpath) {
			return win_err(win.GetLastError())
		}
		if notify != nil { notify(path, false) }
	}
	return .None
}

// remove_all removes path and all its contents recursively.
// If path is a plain file it is deleted directly.
// If path is a directory every descendant is deleted depth-first, then the
// directory itself is removed.
remove_all :: proc(path: string, notify: Notify_Proc = nil, allocator := context.allocator) -> Error {
	k, kerr := stat(path)
	if kerr != .None { return kerr }
	switch k {
	case .Not_Found:
		return .Not_Found
	case .File:
		wpath := win.utf8_to_wstring(path, context.temp_allocator)
		if !win.DeleteFileW(wpath) {
			return win_err(win.GetLastError())
		}
		if notify != nil { notify(path, false) }
	case .Reparse_Dir:
		// Directory symlink/junction: remove the link without recursing into the target.
		wpath := win.utf8_to_wstring(path, context.temp_allocator)
		if !win.RemoveDirectoryW(wpath) {
			return win_err(win.GetLastError())
		}
		if notify != nil { notify(path, true) }
	case .Directory:
		return remove_dir_recursive(path, notify, allocator)
	}
	return .None
}

@(private)
win_err :: proc(ec: win.DWORD) -> Error {
	switch ec {
	case win.ERROR_FILE_NOT_FOUND, win.ERROR_PATH_NOT_FOUND:
		return .Not_Found
	case win.ERROR_ACCESS_DENIED:
		return .Access_Denied
	}
	return .Remove_Failed
}

@(private)
remove_dir_recursive :: proc(path: string, notify: Notify_Proc, allocator: runtime.Allocator) -> Error {
	// Build the glob pattern used to enumerate the directory.
	pattern := winio.join_path(path, "*", context.temp_allocator)
	wpattern := win.utf8_to_wstring(pattern, context.temp_allocator)

	fd: win.WIN32_FIND_DATAW
	h := win.FindFirstFileW(wpattern, &fd)

	first_err := Error.None
	if h != win.INVALID_HANDLE {
		defer win.FindClose(h)
		for {
			// Decode the null-terminated wide filename.
			nlen := 0
			for i in 0..<win.MAX_PATH {
				if fd.cFileName[i] == 0 {
					nlen = i
					break
				}
			}
			name, nerr := win.utf16_to_utf8(fd.cFileName[:nlen], context.temp_allocator)
			if nerr == nil && name != "." && name != ".." {
				child := winio.join_path(path, name, allocator)
				defer delete(child, allocator)

				is_dir     := (fd.dwFileAttributes & win.FILE_ATTRIBUTE_DIRECTORY)     != 0
				is_reparse := (fd.dwFileAttributes & win.FILE_ATTRIBUTE_REPARSE_POINT) != 0
				err: Error
				if is_dir && is_reparse {
					// Directory symlink/junction: remove without following the link.
					wchild := win.utf8_to_wstring(child, context.temp_allocator)
					if !win.RemoveDirectoryW(wchild) {
						err = win_err(win.GetLastError())
					} else if notify != nil {
						notify(child, true)
					}
				} else if is_dir {
					err = remove_dir_recursive(child, notify, allocator)
				} else {
					wchild := win.utf8_to_wstring(child, context.temp_allocator)
					if !win.DeleteFileW(wchild) {
						err = win_err(win.GetLastError())
					} else if notify != nil {
						notify(child, false)
					}
				}
				if err != .None && first_err == .None {
					first_err = err
				}
			}
			if !win.FindNextFileW(h, &fd) {
				break
			}
		}
	}

	if first_err != .None {
		return first_err
	}

	// Remove the (now-empty) directory itself.
	wpath := win.utf8_to_wstring(path, context.temp_allocator)
	if !win.RemoveDirectoryW(wpath) {
		return win_err(win.GetLastError())
	}
	if notify != nil { notify(path, true) }
	return .None
}
