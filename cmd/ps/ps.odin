// package main enumerates running processes via a Toolhelp32 snapshot.
package main

import "core:strings"
import win "core:sys/windows"

// Proc_Entry holds the fields we care about for one running process.
Proc_Entry :: struct {
	pid:  u32,
	ppid: u32,
	name: string,
}

// list_processes returns a snapshot of all currently running processes.
// The caller must free the result with free_proc_list.
list_processes :: proc(allocator := context.allocator) -> ([]Proc_Entry, bool) {
	snap := win.CreateToolhelp32Snapshot(win.TH32CS_SNAPPROCESS, 0)
	if snap == win.INVALID_HANDLE {
		return nil, false
	}
	defer win.CloseHandle(snap)

	result := make([dynamic]Proc_Entry, 0, 64, allocator)

	entry: win.PROCESSENTRY32W
	entry.dwSize = size_of(win.PROCESSENTRY32W)

	if !win.Process32FirstW(snap, &entry) {
		return result[:], true
	}

	for {
		nlen := 0
		for i in 0..<win.MAX_PATH {
			if entry.szExeFile[i] == 0 { nlen = i; break }
		}
		name, nerr := win.utf16_to_utf8(entry.szExeFile[:nlen], allocator)
		if nerr == nil {
			append(&result, Proc_Entry{
				pid  = u32(entry.th32ProcessID),
				ppid = u32(entry.th32ParentProcessID),
				name = name,
			})
		}
		if !win.Process32NextW(snap, &entry) { break }
	}

	return result[:], true
}

// free_proc_list releases memory allocated by list_processes.
free_proc_list :: proc(procs: []Proc_Entry, allocator := context.allocator) {
	for p in procs { delete(p.name, allocator) }
	delete(procs, allocator)
}

// filter_name returns true when entry.name contains substr (case-insensitive).
filter_name :: proc(entry: Proc_Entry, substr: string) -> bool {
	if substr == "" { return true }
	lname   := strings.to_lower(entry.name,  context.temp_allocator)
	lsubstr := strings.to_lower(substr, context.temp_allocator)
	return strings.contains(lname, lsubstr)
}
