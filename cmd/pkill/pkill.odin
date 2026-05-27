// package main enumerates running processes and terminates those whose
// executable filename matches a given pattern.
//
// kill_by_name uses a Toolhelp32 snapshot to enumerate processes atomically.
// Matching is always case-insensitive. Pass Match_Opts.exact = true to require
// a full-name match instead of a substring match.
// Pass Match_Opts.dry_run = true to collect results without actually killing.
package main

import "core:strings"
import win "core:sys/windows"

// Error classifies failures returned by kill_by_name.
Error :: enum {
	None,
	Snapshot_Failed,
	Access_Denied,
	Kill_Failed,
}

// Kill_Result records the outcome for one matched process.
Kill_Result :: struct {
	pid:  u32,
	name: string,
	err:  Error, // .None on success, non-None if termination was refused
}

// Match_Opts controls how kill_by_name matches and acts on processes.
Match_Opts :: struct {
	exact:   bool, // -x: entire exe filename must equal pattern (case-insensitive)
	dry_run: bool, // -n: enumerate matches but do not terminate
}

// kill_by_name finds every process whose exe filename matches pattern and
// terminates it (unless opts.dry_run is true).
//
// Matching is case-insensitive. Without opts.exact, pattern is tested as a
// substring of the exe filename. With opts.exact the full filename must match.
//
// The caller must free the returned slice with free_results.
kill_by_name :: proc(pattern: string, opts: Match_Opts, allocator := context.allocator) -> (results: []Kill_Result, err: Error) {
	snap := win.CreateToolhelp32Snapshot(win.TH32CS_SNAPPROCESS, 0)
	if snap == win.INVALID_HANDLE {
		return nil, .Snapshot_Failed
	}
	defer win.CloseHandle(snap)

	out := make([dynamic]Kill_Result, 0, 8, allocator)

	entry: win.PROCESSENTRY32W
	entry.dwSize = size_of(win.PROCESSENTRY32W)

	if !win.Process32FirstW(snap, &entry) {
		return out[:], .None
	}

	lpattern := strings.to_lower(pattern, context.temp_allocator)

	for {
		// Decode the null-terminated exe filename from the fixed-width field.
		nlen := 0
		for i in 0..<win.MAX_PATH {
			if entry.szExeFile[i] == 0 {
				nlen = i
				break
			}
		}

		name, nerr := win.utf16_to_utf8(entry.szExeFile[:nlen], context.temp_allocator)
		if nerr == nil {
			lname := strings.to_lower(name, context.temp_allocator)
			matched := lname == lpattern if opts.exact else strings.contains(lname, lpattern)

			if matched {
				pid := entry.th32ProcessID
				r := Kill_Result{
					pid  = u32(pid),
					name = strings.clone(name, allocator),
				}

				if !opts.dry_run {
					h := win.OpenProcess(win.PROCESS_TERMINATE, false, pid)
					if h == nil {
						r.err = .Access_Denied
					} else {
						if !win.TerminateProcess(h, 1) {
							r.err = .Kill_Failed
						}
						win.CloseHandle(h)
					}
				}

				append(&out, r)
			}
		}

		if !win.Process32NextW(snap, &entry) {
			break
		}
	}

	return out[:], .None
}

// free_results releases all memory returned by kill_by_name.
free_results :: proc(results: []Kill_Result, allocator := context.allocator) {
	for r in results {
		delete(r.name, allocator)
	}
	delete(results, allocator)
}
