// package main reads the process environment block via GetEnvironmentStringsW.
package main

import "core:strings"
import win "core:sys/windows"

foreign import kernel32 "system:Kernel32.lib"

@(default_calling_convention = "stdcall")
foreign kernel32 {
	GetEnvironmentStringsW  :: proc() -> [^]u16 ---
	FreeEnvironmentStringsW :: proc(penv: [^]u16) -> win.BOOL ---
}

// get_env returns the current process environment as a slice of "NAME=VALUE"
// strings.  The caller must free each string and the slice itself.
get_env :: proc(allocator := context.allocator) -> ([]string, bool) {
	block := GetEnvironmentStringsW()
	if block == nil {
		return nil, false
	}
	defer FreeEnvironmentStringsW(block)

	result := make([dynamic]string, 0, 64, allocator)
	offset := 0
	for {
		// Measure the current null-terminated entry.
		nlen := 0
		for block[offset + nlen] != 0 {
			nlen += 1
		}
		if nlen == 0 { break } // double-null terminator = end of block

		s, err := win.utf16_to_utf8(block[offset : offset+nlen], allocator)
		if err == nil {
			append(&result, s)
		}
		offset += nlen + 1
	}
	return result[:], true
}

// env_name returns the NAME portion of a "NAME=VALUE" string.
env_name :: proc(entry: string) -> string {
	for i := 0; i < len(entry); i += 1 {
		if entry[i] == '=' { return entry[:i] }
	}
	return entry
}

// should_exclude returns true when the entry's name matches any of the
// names in the exclude list (case-insensitive on Windows).
should_exclude :: proc(entry: string, exclude: []string) -> bool {
	name := env_name(entry)
	for ex in exclude {
		if strings.equal_fold(name, ex) { return true }
	}
	return false
}
