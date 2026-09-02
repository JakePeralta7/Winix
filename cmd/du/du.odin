// package main walks directory trees and sums file sizes using Win32 Find APIs.
package main

import "core:fmt"
import win "core:sys/windows"
import "../../internal/winconsole"
import "../../internal/winio"

// Du_Opts controls output behaviour.
Du_Opts :: struct {
	summarize:      bool, // -s: only print the grand total per argument
	all:            bool, // -a: also print sizes for individual files
	human_readable: bool, // -h: human-readable sizes
	block_size:     u64,  // bytes per output block (1024 or 1048576)
	max_depth:      int,  // deepest directory level to print (-1 = unlimited)
}

// format_blocks_human formats a byte count as a human-readable string.
format_blocks_human :: proc(bytes: u64) -> string {
	suffixes := []string{"B", "K", "M", "G", "T", "P", "E"}
	v := f64(bytes)
	idx := 0
	for v >= 1024 && idx < len(suffixes)-1 {
		v /= 1024
		idx += 1
	}
	if idx == 0 {
		return fmt.tprintf("%d%s", bytes, "B")
	}
	if v < 10 { return fmt.tprintf("%.1f%s", v, suffixes[idx]) }
	return fmt.tprintf("%.0f%s", v, suffixes[idx])
}

// print_du_line emits one output line in the form "SIZE\tPATH".
print_du_line :: proc(out: winconsole.Writer, bytes_used: u64, path: string, opts: Du_Opts) {
	if opts.human_readable {
		winconsole.write_string(out, fmt.tprintf("%s\t%s\r\n", format_blocks_human(bytes_used), path))
	} else {
		blocks := bytes_used / opts.block_size
		if bytes_used % opts.block_size != 0 {
			blocks += 1
		}
		winconsole.write_string(out, fmt.tprintf("%d\t%s\r\n", blocks, path))
	}
}

// du_dir recursively sums the sizes of everything under dir.
// Returns total usable bytes. When not summarising, intermediate directories
// are printed as visited. depth is the depth of dir itself (0 = operand).
du_dir :: proc(dir: string, opts: Du_Opts, out: winconsole.Writer, depth: int) -> (total_bytes: u64) {
	pattern  := winio.join_path(dir, "*", context.temp_allocator)
	wpattern := win.utf8_to_wstring(pattern, context.temp_allocator)

	fd: win.WIN32_FIND_DATAW
	h := win.FindFirstFileW(wpattern, &fd)
	if h == win.INVALID_HANDLE {
		return 0
	}
	defer win.FindClose(h)

	for {
		nlen := 0
		for i in 0..<win.MAX_PATH {
			if fd.cFileName[i] == 0 { nlen = i; break }
		}
		name, nerr := win.utf16_to_utf8(fd.cFileName[:nlen], context.temp_allocator)
		if nerr == nil && name != "." && name != ".." {
			is_reparse := fd.dwFileAttributes & win.FILE_ATTRIBUTE_REPARSE_POINT != 0
			full := winio.join_path(dir, name, context.temp_allocator)

			if fd.dwFileAttributes & win.FILE_ATTRIBUTE_DIRECTORY != 0 && !is_reparse {
				// Always descend to compute the full total; gating only controls
				// whether this directory is printed (depth limit acts like -s).
				depth_within := opts.max_depth < 0 || depth+1 <= opts.max_depth
				sub := du_dir(full, opts, out, depth+1)
				if !opts.summarize && depth_within {
					print_du_line(out, sub, full, opts)
				}
				total_bytes += sub
			} else {
				size := u64(fd.nFileSizeHigh) << 32 | u64(fd.nFileSizeLow)
				if opts.all && !opts.summarize {
					print_du_line(out, size, full, opts)
				}
				total_bytes += size
			}
		}
		if !win.FindNextFileW(h, &fd) { break }
	}
	return
}

// path_exists returns true when path refers to an existing file or directory.
path_exists :: proc(path: string) -> bool {
	wpath := win.utf8_to_wstring(path, context.temp_allocator)
	return win.GetFileAttributesW(wpath) != winio.INVALID_FILE_ATTRS
}

// du_path returns the total byte usage for path (file or directory).
// Intermediate directory sizes are printed to out when !opts.summarize.
du_path :: proc(path: string, opts: Du_Opts, out: winconsole.Writer) -> u64 {
	wpath := win.utf8_to_wstring(path, context.temp_allocator)
	attrs := win.GetFileAttributesW(wpath)
	if attrs == winio.INVALID_FILE_ATTRS {
		return 0
	}
	if attrs & win.FILE_ATTRIBUTE_DIRECTORY != 0 {
		return du_dir(path, opts, out, 0)
	}
	// Plain file: use FindFirstFileW to retrieve the size.
	fd: win.WIN32_FIND_DATAW
	h := win.FindFirstFileW(wpath, &fd)
	if h == win.INVALID_HANDLE { return 0 }
	win.FindClose(h)
	size := u64(fd.nFileSizeHigh) << 32 | u64(fd.nFileSizeLow)
	return size
}