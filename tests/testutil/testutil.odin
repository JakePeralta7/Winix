// Package testutil holds helpers shared by Winix integration tests.
package testutil

import "core:strings"
import win "core:sys/windows"

// remove_tree deletes path and everything below it using Win32 file APIs.
// os.remove_all falls back to SHFileOperationW for non-empty directories, which
// invokes shell path resolution and raises handled WebDAV exceptions on some
// Windows machines; the Odin test runner treats those as test failures.
remove_tree :: proc(path: string) {
	if path == "" { return }

	wpath := win.utf8_to_wstring(path, context.temp_allocator)
	pattern := strings.concatenate({path, "\\*"}, context.temp_allocator)
	wpattern := win.utf8_to_wstring(pattern, context.temp_allocator)

	data: win.WIN32_FIND_DATAW
	find := win.FindFirstFileW(wpattern, &data)
	if find == win.INVALID_HANDLE_VALUE {
		win.DeleteFileW(wpath)
		win.RemoveDirectoryW(wpath)
		return
	}
	defer win.FindClose(find)

	for {
		n := 0
		for n < len(data.cFileName) && data.cFileName[n] != 0 {
			n += 1
		}
		name, err := win.utf16_to_utf8(data.cFileName[:n], context.temp_allocator)
		if err == nil && name != "." && name != ".." {
			child := strings.concatenate({path, "\\", name}, context.temp_allocator)
			if data.dwFileAttributes & win.FILE_ATTRIBUTE_DIRECTORY != 0 {
				remove_tree(child)
			} else {
				wchild := win.utf8_to_wstring(child, context.temp_allocator)
				win.DeleteFileW(wchild)
			}
		}
		if !win.FindNextFileW(find, &data) { break }
	}

	win.RemoveDirectoryW(wpath)
}
