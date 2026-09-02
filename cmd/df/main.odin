package main

import "core:fmt"
import "core:os"
import "core:strings"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: df [OPTION]... [FILE]...
Show information about the filesystem on which each FILE resides,
or all filesystems by default.

  -i, --inodes          list inode information instead of block usage
  -h, --human-readable  print sizes in human-readable form (e.g. 4.2G)
  -k                    use 1024-byte blocks (default)
  -m                    use 1,048,576-byte blocks
  -P, --portability     use the POSIX output format (1 K blocks)
  -T, --print-type      print filesystem type
      --help            display this help and exit
      --version         output version information and exit

Sizes are in 1 KiB blocks by default.
`

// Inode_Bytes is the nominal allocation unit each "inode" roughly assumes on
// Windows, used only to present a meaningful -i column (Windows has no real
// inode table; values are best-effort from volume info).
Inode_Bytes :: 4096

main :: proc() {
	human, inodes, print_type, mb, posix, k, help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'i', long = "inodes",         kind = .Bool_Last_Wins, target = &inodes,     value_if_set = true},
			{short = 'h', long = "human-readable", kind = .Bool_Last_Wins, target = &human,      value_if_set = true},
			{short = 'k',                         kind = .Bool_Last_Wins, target = &k,          value_if_set = true},
			{short = 'm',                         kind = .Bool_Last_Wins, target = &mb,         value_if_set = true},
			{short = 'P', long = "portability",   kind = .Bool_Last_Wins, target = &posix,      value_if_set = true},
			{short = 'T', long = "print-type",    kind = .Bool_Last_Wins, target = &print_type, value_if_set = true},
			{             long = "help",          kind = .Bool_Last_Wins, target = &help,       value_if_set = true},
			{             long = "version",       kind = .Bool_Last_Wins, target = &version,    value_if_set = true},
		},
	}

	args := os.args[1:] if len(os.args) > 1 else []string{}
	parsed, perr, tok := cliflag.parse(args, spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "df: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'df --help'.\r\n")
		os.exit(2)
	}
	if help    { winconsole.write_string(out, USAGE); os.exit(0) }
	if version { winconsole.write_line(out, "df (winix) " + VERSION); os.exit(0) }

	// Choose the block-size divisor: human overrides; otherwise 1K default,
	// 1M when -m, still 1K under -k/-P.
	divisor: u64 = 1024
	if human {
		divisor = 0
	} else if mb {
		divisor = 1024 * 1024
	}

	print_header(out, divisor, print_type, inodes)
	exit_code := 0

	if len(parsed.rest) == 0 {
		disks := all_local_disks()
		defer delete(disks)
		for info in disks {
			print_disk(out, info, divisor, print_type, inodes)
		}
	} else {
		for path in parsed.rest {
			info, ok := query_disk(path)
			if !ok {
				winconsole.write_string(errw, "df: ")
				winconsole.write_string(errw, path)
				winconsole.write_string(errw, ": cannot access\r\n")
				exit_code = 1
				continue
			}
			info.root = path
			print_disk(out, info, divisor, print_type, inodes)
		}
	}

	os.exit(exit_code)
}

print_header :: proc(out: winconsole.Writer, divisor: u64, print_type, inodes: bool) {
	type_fmt := "%-8s "
	if !print_type {
		type_fmt = ""
	}

	fmtstr: string
	if inodes {
		fmtstr = strings.concatenate({"%-16s ", type_fmt, "%12s %12s %12s %4s\r\n"})
	} else if divisor == 0 {
		fmtstr = strings.concatenate({"%-16s ", type_fmt, "%6s %6s %6s %4s\r\n"})
	} else {
		fmtstr = strings.concatenate({"%-16s ", type_fmt, "%12s %12s %12s %4s\r\n"})
	}
	defer delete(fmtstr)

	name: string
	if inodes {
		name = "Filesystem"
		if print_type {
			winconsole.write_string(out, fmt.tprintf(fmtstr, name,
				"Type", "Inodes", "IUsed", "IFree", "IUse%"))
		} else {
			winconsole.write_string(out, fmt.tprintf(fmtstr, name,
				"Inodes", "IUsed", "IFree", "IUse%"))
		}
	} else if divisor == 0 {
		name = "Filesystem"
		if print_type {
			winconsole.write_string(out, fmt.tprintf(fmtstr, name,
				"Type", "Size", "Used", "Avail", "Use%"))
		} else {
			winconsole.write_string(out, fmt.tprintf(fmtstr, name,
				"Size", "Used", "Avail", "Use%"))
		}
	} else {
		name = "Filesystem"
		if print_type {
			winconsole.write_string(out, fmt.tprintf(fmtstr, name,
				"Type", "1K-blocks", "Used", "Available", "Use%"))
		} else {
			winconsole.write_string(out, fmt.tprintf(fmtstr, name,
				"1K-blocks", "Used", "Available", "Use%"))
		}
	}
}

print_disk :: proc(out: winconsole.Writer, info: Disk_Info, divisor: u64, print_type, inodes: bool) {
	type_col := ""
	if print_type {
		type_col = "%-8s "
	}

	if inodes {
		total_inodes := info.total / Inode_Bytes
		used_inodes  := (info.total - info.free) / Inode_Bytes
		free_inodes  := info.avail / Inode_Bytes
		use_pct := 0 if total_inodes == 0 else int(used_inodes * 100 / total_inodes)

		if print_type {
			winconsole.write_string(out, fmt.tprintf("%-16s %-8s %12d %12d %12d %3d%%\r\n",
				info.root, info.fs_type, total_inodes, used_inodes, free_inodes, use_pct))
		} else {
			winconsole.write_string(out, fmt.tprintf("%-16s %12d %12d %12d %3d%%\r\n",
				info.root, total_inodes, used_inodes, free_inodes, use_pct))
		}
		return
	}

	used    := info.total - info.free
	use_pct := 0 if info.total == 0 else int(used * 100 / info.total)

	if divisor == 0 {
		if print_type {
			winconsole.write_string(out, fmt.tprintf("%-16s %-8s %6s %6s %6s %3d%%\r\n",
				info.root, info.fs_type,
				format_size_human(info.total), format_size_human(used), format_size_human(info.avail),
				use_pct))
		} else {
			winconsole.write_string(out, fmt.tprintf("%-16s %6s %6s %6s %3d%%\r\n",
				info.root,
				format_size_human(info.total), format_size_human(used), format_size_human(info.avail),
				use_pct))
		}
		return
	}

	if print_type {
		winconsole.write_string(out, fmt.tprintf("%-16s %-8s %12s %12s %12s %3d%%\r\n",
			info.root, info.fs_type,
			format_size_blocks(info.total, divisor),
			format_size_blocks(used, divisor),
			format_size_blocks(info.avail, divisor),
			use_pct))
	} else {
		winconsole.write_string(out, fmt.tprintf("%-16s %12s %12s %12s %3d%%\r\n",
			info.root,
			format_size_blocks(info.total, divisor),
			format_size_blocks(used, divisor),
			format_size_blocks(info.avail, divisor),
			use_pct))
	}
}

// format_size_blocks expresses bytes in blocks of the given divisor size.
format_size_blocks :: proc(bytes, divisor: u64) -> string {
	if divisor <= 1 {
		return fmt.tprintf("%d", bytes)
	}
	return fmt.tprintf("%d", bytes / divisor)
}