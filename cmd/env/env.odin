// package main reads and modifies the process environment via Win32.
package main

import "core:os"
import "core:strings"
import win "core:sys/windows"

foreign import kernel32 "system:Kernel32.lib"

@(default_calling_convention = "stdcall")
foreign kernel32 {
	GetEnvironmentStringsW  :: proc() -> [^]u16 ---
	FreeEnvironmentStringsW :: proc(penv: [^]u16) -> win.BOOL ---
}

// get_env returns a copy of the current process environment block as NAME=VALUE strings.
get_env :: proc(allocator := context.allocator) -> ([]string, bool) {
	block := GetEnvironmentStringsW()
	if block == nil {
		return nil, false
	}
	defer FreeEnvironmentStringsW(block)

	result := make([dynamic]string, 0, 64, allocator)
	offset := 0
	for {
		nlen := 0
		for block[offset + nlen] != 0 {
			nlen += 1
		}
		if nlen == 0 { break }
		s, err := win.utf16_to_utf8(block[offset : offset+nlen], allocator)
		if err == nil {
			append(&result, s)
		}
		offset += nlen + 1
	}
	return result[:], true
}

// env_name returns the name portion of a NAME=VALUE entry.
env_name :: proc(entry: string) -> string {
	for i := 0; i < len(entry); i += 1 {
		if entry[i] == '=' { return entry[:i] }
	}
	return entry
}

// should_exclude reports whether entry's name appears in exclude, ignoring case.
should_exclude :: proc(entry: string, exclude: []string) -> bool {
	name := env_name(entry)
	for ex in exclude {
		if strings.equal_fold(name, ex) { return true }
	}
	return false
}

// clone_env_string copies s into allocator.
clone_env_string :: proc(s: string, allocator := context.allocator) -> string {
	cloned, err := strings.clone(s, allocator)
	return cloned if err == nil else ""
}

// build_entries returns a fresh environment with excluded names removed and assignments
// applied. Existing variables are replaced in place; new ones are appended.
build_entries :: proc(base: []string, exclude: []string, assignments: []string, ignore_env: bool, allocator := context.allocator) -> []string {
	result := make([dynamic]string, 0, len(base) + len(assignments), allocator)

	if !ignore_env {
		for entry in base {
			if should_exclude(entry, exclude) { continue }
			append(&result, clone_env_string(entry, allocator))
		}
	}

	for assignment in assignments {
		eq := strings.index_byte(assignment, '=')
		if eq <= 0 { continue }
		name := assignment[:eq]
		replaced := false
		for i in 0..<len(result) {
			if strings.equal_fold(env_name(result[i]), name) {
				delete(result[i])
				result[i] = clone_env_string(assignment, allocator)
				replaced = true
				break
			}
		}
		if !replaced {
			append(&result, clone_env_string(assignment, allocator))
		}
	}

	return result[:]
}

// free_entries releases every string and the slice allocated by build_entries.
free_entries :: proc(entries: []string) {
	for entry in entries { delete(entry) }
	delete(entries)
}

// inheritable_std_file wraps a standard handle in an inheritable duplicate so the
// child gets the same console or redirected streams. The duplicate can be closed
// once CreateProcessW has run; the returned handle is kept only for that cleanup.
inheritable_std_file :: proc(which: win.DWORD) -> (^os.File, win.HANDLE) {
	original := win.GetStdHandle(which)
	if original == nil || original == win.INVALID_HANDLE_VALUE {
		return nil, nil
	}

	current := win.GetCurrentProcess()
	duplicate: win.HANDLE
	if win.DuplicateHandle(current, original, current, &duplicate, 0, win.BOOL(true), win.DUPLICATE_SAME_ACCESS) {
		return os.new_file(uintptr(duplicate), ""), duplicate
	}

	return os.new_file(uintptr(original), ""), nil
}

// run_command starts command with the supplied environment, inheriting the current
// standard handles, and returns its exit code.
run_command :: proc(command: []string, environment: []string) -> (int, os.Error) {
	stdin_file,  stdin_dup  := inheritable_std_file(win.STD_INPUT_HANDLE)
	stdout_file, stdout_dup := inheritable_std_file(win.STD_OUTPUT_HANDLE)
	stderr_file, stderr_dup := inheritable_std_file(win.STD_ERROR_HANDLE)
	defer if stdin_dup  != nil { win.CloseHandle(stdin_dup) }
	defer if stdout_dup != nil { win.CloseHandle(stdout_dup) }
	defer if stderr_dup != nil { win.CloseHandle(stderr_dup) }

	process, start_err := os.process_start(os.Process_Desc{
		command = command,
		env = environment,
		stdin = stdin_file,
		stdout = stdout_file,
		stderr = stderr_file,
	})
	if start_err != nil { return 0, start_err }

	state, wait_err := os.process_wait(process)
	if wait_err != nil { return 0, wait_err }
	return state.exit_code, nil
}
