// package main enumerates running processes and terminates those whose
// executable filename or command line matches a given pattern.
//
// kill_by_name uses a Toolhelp32 snapshot to enumerate processes atomically.
// Matching is always case-insensitive. Match_Opts configures the matching and
// selection behaviour (exact, full, inverse, oldest/newest, session, parent,
// dry-run).
package main

import "core:strings"
import win "core:sys/windows"

foreign import kernel32 "system:Kernel32.lib"

@(default_calling_convention = "stdcall")
foreign kernel32 {
	QueryFullProcessImageNameW :: proc(
		hProcess:            win.HANDLE,
		dwFlags:            win.DWORD,
		lpExeName:          win.LPWSTR,
		lpdwSize:           ^win.DWORD,
	) -> win.BOOL ---
	ProcessIdToSessionId :: proc(
		dwProcessId:      win.DWORD,
		pSessionId:       ^win.DWORD,
	) -> win.BOOL ---
}

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
	pattern:  string, // matched against exe name (or full path with opts.full)
	exact:    bool,   // -x: entire filename must equal pattern
	full:     bool,   // -f: match against the full image path, not just the name
	inverse:  bool,   // -v: match processes that do NOT match
	newest:   bool,   // -n: select only the most recently started match
	oldest:   bool,   // -o: select only the earliest started match
	dry_run:  bool,   // -d: enumerate matches but do not terminate
	// Selectors narrow the candidate set before pattern matching.
	parent_pids: []u32, // -P: only processes whose parent is in this list
	sessions:    []u32, // -s: only processes in one of these session IDs
}

// Proc_Info holds the metadata gathered for a matching process.
Proc_Info :: struct {
	pid:       u32,
	ppid:      u32,
	name:      string, // szExeFile (allocated)
	full_path: string, // full image path when opts.full (allocated; may be "")
}

// kill_by_name finds processes matching opts.pattern (per opts) and terminates
// them (unless opts.dry_run is true).
//
// When opts.newest or opts.oldest is set, only a single matching process is
// returned. Selectors (-P, -s) restrict the candidate set.
//
// The caller must free the returned slice with free_results.
kill_by_name :: proc(opts: Match_Opts, allocator := context.allocator) -> (results: []Kill_Result, err: Error) {
	snap := win.CreateToolhelp32Snapshot(win.TH32CS_SNAPPROCESS, 0)
	if snap == win.INVALID_HANDLE {
		return nil, .Snapshot_Failed
	}
	defer win.CloseHandle(snap)

	matched := collect_matches(snap, opts, allocator)
	defer {
		for p in matched {
			delete(p.name, allocator)
			if p.full_path != "" { delete(p.full_path, allocator) }
		}
		delete(matched, allocator)
	}

	// Select the set to act on: newest/oldest pick a single process.
	chosen := matched
	if opts.newest || opts.oldest {
		if idx, ok := pick_newest_oldest(matched, opts.newest); ok {
			chosen = matched[idx:idx+1]
		} else {
			chosen = nil
		}
	}

	out := make([dynamic]Kill_Result, 0, 8, allocator)
	for p in chosen {
		pid := p.pid
		r := Kill_Result{
			pid  = pid,
			name = strings.clone(p.name, allocator),
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
	return out[:], .None
}

// collect_matches enumerates all processes, applies the -P/-s selectors, and
// returns those whose name (or full path) matches opts.pattern.
// The returned strings are allocated with allocator and owned by the caller.
@(private)
collect_matches :: proc(snap: win.HANDLE, opts: Match_Opts, allocator := context.allocator) -> []Proc_Info {
	out := make([dynamic]Proc_Info, 0, 32, allocator)

	entry: win.PROCESSENTRY32W
	entry.dwSize = size_of(win.PROCESSENTRY32W)
	if !win.Process32FirstW(snap, &entry) {
		return out[:]
	}

	lpattern := strings.to_lower(opts.pattern, context.temp_allocator)

	for {
		pid  := u32(entry.th32ProcessID)
		ppid := u32(entry.th32ParentProcessID)

		// -P: parent must be in the allowed list.
		allowed := true
		if len(opts.parent_pids) > 0 && !contains_u32(opts.parent_pids, ppid) {
			allowed = false
		}

		// -s: process session must be in the allowed list.
		if allowed && len(opts.sessions) > 0 {
			sess, sok := process_session(pid)
			if !sok || !contains_u32(opts.sessions, sess) {
				allowed = false
			}
		}

		if allowed {
			// Decode the exe filename.
			nlen := 0
			for i in 0..<win.MAX_PATH {
				if entry.szExeFile[i] == 0 { nlen = i; break }
			}
			name, nerr := win.utf16_to_utf8(entry.szExeFile[:nlen], context.temp_allocator)
			if nerr == nil {
				full_path := ""
				matchable := name
				if opts.full {
					full_path = process_full_path(pid, allocator)
					if full_path != "" {
						matchable = full_path
					}
				}

				lname := strings.to_lower(matchable, context.temp_allocator)
				matched := lname == lpattern if opts.exact else strings.contains(lname, lpattern)
				if opts.inverse {
					matched = !matched
				}

				if matched {
					append(&out, Proc_Info{
						pid       = pid,
						ppid      = ppid,
						name      = strings.clone(name, allocator),
						full_path = strings.clone(full_path, allocator),
					})
				} else {
					if full_path != "" { delete(full_path, allocator) }
				}
			}
		}

		if !win.Process32NextW(snap, &entry) {
			break
		}
	}
	return out[:]
}

// pick_newest_oldest returns the index of the newest (when newest=true) or
// oldest candidate among matches, based on process creation time. Returns
// (ok=false) when no recipient can be timed.
@(private)
pick_newest_oldest :: proc(matches: []Proc_Info, newest: bool) -> (idx: int, ok: bool) {
	best_idx := -1
	best_ticks: u64
	for i in 0..<len(matches) {
		ticks, okk := process_start_ticks(matches[i].pid)
		if !okk { continue }
		if best_idx < 0 || (newest && ticks > best_ticks) || (!newest && ticks < best_ticks) {
			best_idx = i
			best_ticks = ticks
		}
	}
	if best_idx < 0 {
		return 0, false
	}
	return best_idx, true
}

@(private)
contains_u32 :: proc(list: []u32, v: u32) -> bool {
	for x in list {
		if x == v { return true }
	}
	return false
}

// free_results releases all memory returned by kill_by_name.
free_results :: proc(results: []Kill_Result, allocator := context.allocator) {
	for r in results {
		delete(r.name, allocator)
	}
	delete(results, allocator)
}

// process_full_path returns the full path of the executable of pid, or "" when
// it cannot be resolved. Caller must free ("" is a static empty string).
process_full_path :: proc(pid: u32, allocator := context.allocator) -> string {
	h := win.OpenProcess(win.PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
	if h == nil { return "" }
	defer win.CloseHandle(h)

	buf: [1024]u16
	size: win.DWORD = len(buf)
	if !QueryFullProcessImageNameW(h, 0, &buf[0], &size) {
		return ""
	}
	u, err := win.utf16_to_utf8(buf[:size], allocator)
	if err != nil { return "" }
	return u
}

// process_session returns the terminal session ID hosting pid.
process_session :: proc(pid: u32) -> (u32, bool) {
	session_id: win.DWORD
	if !ProcessIdToSessionId(win.DWORD(pid), &session_id) {
		return 0, false
	}
	return session_id, true
}

// process_start_ticks returns the creation time of pid as a comparable 64-bit
// tick count, or false on failure.
process_start_ticks :: proc(pid: u32) -> (u64, bool) {
	h := win.OpenProcess(win.PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
	if h == nil { return 0, false }
	defer win.CloseHandle(h)

	create, exit, kernel, user: win.FILETIME
	if !win.GetProcessTimes(h, &create, &exit, &kernel, &user) {
		return 0, false
	}
	ticks := u64(create.dwHighDateTime) << 32 | u64(create.dwLowDateTime)
	return ticks, true
}