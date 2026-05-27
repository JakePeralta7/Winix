// package main queries disk free space using the Win32 API.
package main

import "core:fmt"
import win "core:sys/windows"

foreign import kernel32 "system:Kernel32.lib"

@(default_calling_convention = "stdcall")
foreign kernel32 {
	// GetDiskFreeSpaceExW accepts ^ULARGE_INTEGER for the last three params.
	// We pass ^u64 – ABI-compatible because ULARGE_INTEGER is a union whose
	// QuadPart (u64) occupies the same 8 bytes at offset 0.
	GetDiskFreeSpaceExW :: proc(
		lpDirectoryName:              win.LPCWSTR,
		lpFreeBytesAvailableToCaller: ^u64,
		lpTotalNumberOfBytes:         ^u64,
		lpTotalNumberOfFreeBytes:     ^u64,
	) -> win.BOOL ---

	GetLogicalDrives :: proc() -> win.DWORD ---
	GetDriveTypeW    :: proc(lpRootPathName: win.LPCWSTR) -> win.UINT ---
}

DRIVE_FIXED    :: win.UINT(3)
DRIVE_REMOTE   :: win.UINT(4)
DRIVE_RAMDISK  :: win.UINT(6)

// Disk_Info holds the queried values for one filesystem.
Disk_Info :: struct {
	root:       string, // e.g. "C:\"
	total:      u64,    // total bytes
	free:       u64,    // total free bytes
	avail:      u64,    // bytes available to caller (may differ with quotas)
}

// query_disk fills a Disk_Info for path (any path on the target volume).
// Returns false when GetDiskFreeSpaceExW fails.
query_disk :: proc(path: string) -> (Disk_Info, bool) {
	wpath := win.utf8_to_wstring(path, context.temp_allocator)
	info: Disk_Info
	info.root = path
	ok := GetDiskFreeSpaceExW(wpath, &info.avail, &info.total, &info.free)
	return info, bool(ok)
}

// all_local_disks returns Disk_Info for every fixed or RAM drive present.
all_local_disks :: proc() -> []Disk_Info {
	mask   := GetLogicalDrives()
	result := make([dynamic]Disk_Info, 0, 4)
	for i in 0..<26 {
		if mask & (win.DWORD(1) << uint(i)) == 0 { continue }
		// Build "X:\" – allocate from temp so the string survives the function.
		drive_root := [3]u8{u8('A') + u8(i), ':', '\\'}
		letter     := fmt.tprintf("%s", string(drive_root[:]))
		wroot      := win.utf8_to_wstring(letter, context.temp_allocator)
		dt         := GetDriveTypeW(wroot)
		if dt != DRIVE_FIXED && dt != DRIVE_RAMDISK && dt != DRIVE_REMOTE { continue }
		info, ok := query_disk(letter)
		if ok { append(&result, info) }
	}
	return result[:]
}

// format_size_1k returns the size expressed in 1 KiB blocks.
format_size_1k :: proc(bytes: u64) -> string {
	return fmt.tprintf("%d", bytes / 1024)
}

// format_size_human returns a human-readable size string (K/M/G/T).
format_size_human :: proc(bytes: u64) -> string {
	if bytes < 1024 { return fmt.tprintf("%dB", bytes) }
	v := f64(bytes)
	suffixes := []string{"K", "M", "G", "T", "P"}
	idx := 0
	for v >= 1024 && idx < len(suffixes)-1 {
		v /= 1024
		idx += 1
	}
	if v < 10 { return fmt.tprintf("%.1f%s", v, suffixes[idx]) }
	return fmt.tprintf("%.0f%s", v, suffixes[idx])
}
