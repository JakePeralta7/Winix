// package main enumerates running processes via a Toolhelp32 snapshot.
package main

import "core:strings"
import win "core:sys/windows"

foreign import kernel32 "system:Kernel32.lib"
foreign import advapi32 "system:Advapi32.lib"

@(default_calling_convention = "stdcall")
foreign kernel32 {
	ProcessIdToSessionId :: proc(
		dwProcessId:      win.DWORD,
		pSessionId:       ^win.DWORD,
	) -> win.BOOL ---
}

// Proc_Entry holds the fields we care about for one running process.
Proc_Entry :: struct {
	pid:        u32,
	ppid:       u32,
	session_id: u32,
	name:       string, // szExeFile
	owner:      string, // "" unless owner lookup succeeded
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
			sess, _ := process_session(u32(entry.th32ProcessID))
			append(&result, Proc_Entry{
				pid        = u32(entry.th32ProcessID),
				ppid       = u32(entry.th32ParentProcessID),
				session_id = sess,
				name       = name,
			})
		}
		if !win.Process32NextW(snap, &entry) { break }
	}

	return result[:], true
}

// free_proc_list releases memory allocated by list_processes.
free_proc_list :: proc(procs: []Proc_Entry, allocator := context.allocator) {
	for p in procs {
		delete(p.name, allocator)
		if p.owner != "" { delete(p.owner, allocator) }
	}
	delete(procs, allocator)
}

// process_session returns the terminal session ID hosting pid.
@(private)
process_session :: proc(pid: u32) -> (u32, bool) {
	session_id: win.DWORD
	if !ProcessIdToSessionId(win.DWORD(pid), &session_id) {
		return 0, false
	}
	return session_id, true
}

// resolve_owner returns the owner account name of pid, or "" on failure.
// The returned string is allocated with allocator ("" is static).
resolve_owner :: proc(pid: u32, allocator := context.allocator) -> string {
	h := win.OpenProcess(win.PROCESS_QUERY_INFORMATION, false, pid)
	if h == nil {
		return ""
	}
	defer win.CloseHandle(h)

	tok: win.HANDLE
	if !win.OpenProcessToken(h, win.TOKEN_QUERY, &tok) {
		return ""
	}
	defer win.CloseHandle(tok)

	// GetTokenInformation(TokenUser) requires first querying the buffer size.
	needed: win.DWORD
	win.GetTokenInformation(tok, .TokenUser, nil, 0, &needed)
	if needed == 0 {
		return ""
	}
	buf := make([]u8, needed, allocator)
	defer delete(buf, allocator)

	ret: win.DWORD
	if !win.GetTokenInformation(tok, .TokenUser, raw_data(buf), needed, &ret) {
		return ""
	}

	token_user := (^win.TOKEN_USER)(raw_data(buf))
	sid := token_user.User.Sid
	if sid == nil {
		return ""
	}

	name_len: win.DWORD = 0
	domain_len: win.DWORD = 0
	use: win.SID_NAME_USE
	// First call sizes the buffers.
	win.LookupAccountSidW(nil, sid, nil, &name_len, nil, &domain_len, &use)
	if name_len == 0 {
		return ""
	}
	name_buf := make([]u16, name_len, allocator)
	defer delete(name_buf, allocator)
	dom_buf  := make([]u16, domain_len, allocator)
	defer delete(dom_buf, allocator)

	win.LookupAccountSidW(nil, sid, raw_data(name_buf), &name_len, raw_data(dom_buf), &domain_len, &use)

	name, nerr := win.utf16_to_utf8(name_buf[:name_len], allocator)
	if nerr != nil { return "" }
	return name
}