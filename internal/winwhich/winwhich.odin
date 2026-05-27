package winwhich

import "base:runtime"
import "core:os"
import "core:strings"
import win "core:sys/windows"

Error :: enum {
	None,
	Not_Found,
}

// find searches the PATH environment variable for an executable named `name`.
// If all_matches is false, only the first match is returned.
// If name contains a path separator the file is checked directly instead.
// The caller must call free_results on the returned slice.
find :: proc(name: string, all_matches: bool, allocator := context.allocator) -> (paths: []string, err: Error) {
	// If name contains a path separator, check it directly.
	if strings.contains_any(name, "/\\") {
		sep := strings.last_index_any(name, "/\\")
		dir := name[:sep]
		if real, ok := real_path(dir, name, allocator); ok {
			out := make([]string, 1, allocator)
			out[0] = real
			return out, .None
		}
		return nil, .Not_Found
	}

	path_env    := os.get_env("PATH",    context.temp_allocator)
	pathext_env := os.get_env("PATHEXT", context.temp_allocator)
	if len(pathext_env) == 0 {
		pathext_env = ".COM;.EXE;.BAT;.CMD"
	}

	dirs := strings.split(path_env,    ";", context.temp_allocator)
	exts := strings.split(pathext_env, ";", context.temp_allocator)

	// Does name already carry an extension?
	dot_pos  := strings.last_index(name, ".")
	sep_pos  := strings.last_index_any(name, "/\\")
	has_ext  := dot_pos > sep_pos && dot_pos >= 0

	result := make([dynamic]string, 0, 4, allocator)

	outer: for dir in dirs {
		if len(dir) == 0 { continue }

		if has_ext {
			full := strings.concatenate({dir, "\\", name}, context.temp_allocator)
			if real, ok := real_path(dir, full, allocator); ok {
				append(&result, real)
				if !all_matches { break outer }
			}
		} else {
			for ext in exts {
				candidate := strings.concatenate({dir, "\\", name, ext}, context.temp_allocator)
				if real, ok := real_path(dir, candidate, allocator); ok {
					append(&result, real)
					if !all_matches { break outer }
					break // one extension per directory
				}
			}
		}
	}

	// Fall back to (or supplement with) the App Paths registry keys.
	if all_matches || len(result) == 0 {
		search_app_paths(name, exts, has_ext, all_matches, &result, allocator)
	}

	if len(result) == 0 {
		delete(result)
		return nil, .Not_Found
	}
	return result[:], .None
}

// free_results releases all memory returned by find.
free_results :: proc(paths: []string, allocator := context.allocator) {
	for p in paths {
		delete(p, allocator)
	}
	if paths != nil {
		delete(paths, allocator)
	}
}

// real_path checks whether candidate exists (and is not a directory), and if so
// returns the path rebuilt with the filesystem's actual filename casing.
// dir is the parent directory component of candidate.
@(private)
real_path :: proc(dir, candidate: string, allocator := context.allocator) -> (path: string, ok: bool) {
	wcandidate := win.utf8_to_wstring(candidate, context.temp_allocator)
	fd: win.WIN32_FIND_DATAW
	h := win.FindFirstFileW(wcandidate, &fd)
	if h == win.INVALID_HANDLE { return "", false }
	win.FindClose(h)
	if fd.dwFileAttributes & win.FILE_ATTRIBUTE_DIRECTORY != 0 { return "", false }

	// cFileName holds the real on-disk name with correct casing.
	real_name, _ := win.utf16_to_utf8(fd.cFileName[:], context.temp_allocator)
	full := strings.concatenate({dir, "\\", real_name}, allocator)
	return full, true
}

APP_PATHS_SUBKEY :: `SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths`

// search_app_paths appends any App Paths registry matches for name into result.
@(private)
search_app_paths :: proc(name: string, exts: []string, has_ext: bool, all_matches: bool, result: ^[dynamic]string, allocator: runtime.Allocator) {
	roots := []win.HKEY{win.HKEY_CURRENT_USER, win.HKEY_LOCAL_MACHINE}
	if has_ext {
		for root in roots {
			if p, ok := query_app_path(root, name, allocator); ok {
				append(result, p)
				if !all_matches { return }
			}
		}
	} else {
		for ext in exts {
			key_name := strings.concatenate({name, ext}, context.temp_allocator)
			for root in roots {
				if p, ok := query_app_path(root, key_name, allocator); ok {
					append(result, p)
					if !all_matches { return }
					break // one root per extension
				}
			}
		}
	}
}

// query_app_path reads the default value of App Paths\<key_name> from root.
// RegGetValueW with RRF_RT_REG_EXPAND_SZ automatically expands %ENV% variables.
@(private)
query_app_path :: proc(root: win.HKEY, key_name: string, allocator: runtime.Allocator) -> (path: string, ok: bool) {
	subkey  := strings.concatenate({APP_PATHS_SUBKEY, `\`, key_name}, context.temp_allocator)
	wsubkey := win.utf8_to_wstring(subkey, context.temp_allocator)

	flags := win.DWORD(win.RRF_RT_REG_SZ | win.RRF_RT_REG_EXPAND_SZ)

	// First call: get required buffer size in bytes.
	n: win.DWORD
	if win.RegGetValueW(root, wsubkey, nil, flags, nil, nil, &n) != 0 {
		return "", false
	}

	// Second call: read the UTF-16LE data.
	buf := make([]u16, (int(n) + 1) / 2 + 1, context.temp_allocator)
	if win.RegGetValueW(root, wsubkey, nil, flags, nil, rawptr(raw_data(buf)), &n) != 0 {
		return "", false
	}

	// Strip null terminators.
	nchars := int(n) / 2
	for nchars > 0 && buf[nchars-1] == 0 {
		nchars -= 1
	}

	p, perr := win.utf16_to_utf8(buf[:nchars], allocator)
	if perr != nil { return "", false }

	// Some App Paths entries wrap the path in double-quotes.
	if len(p) >= 2 && p[0] == '"' && p[len(p)-1] == '"' {
		unquoted := strings.clone(p[1:len(p)-1], allocator)
		delete(p, allocator)
		p = unquoted
	}
	return p, true
}
