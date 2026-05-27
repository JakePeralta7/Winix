package main

import "core:fmt"
import "core:os"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: df [-h] [--help] [--version] [path ...]
Report disk space usage for each filesystem.

  -h, --human-readable  print sizes in human-readable form (e.g. 4.2G)
  --help                print this message and exit
  --version             print version and exit

With no path arguments all local fixed drives are shown.
Sizes are in 1 KiB blocks unless -h is given.
`

print_header :: proc(out: winconsole.Writer, human: bool) {
	if human {
		winconsole.write_string(out, fmt.tprintf("%-16s %6s %6s %6s %4s\r\n",
			"Filesystem", "Size", "Used", "Avail", "Use%"))
	} else {
		winconsole.write_string(out, fmt.tprintf("%-16s %12s %12s %12s %4s\r\n",
			"Filesystem", "1K-blocks", "Used", "Available", "Use%"))
	}
}

print_disk :: proc(out: winconsole.Writer, info: Disk_Info, human: bool) {
	used    := info.total - info.free
	use_pct := 0 if info.total == 0 else int(used * 100 / info.total)

	if human {
		winconsole.write_string(out, fmt.tprintf("%-16s %6s %6s %6s %3d%%\r\n",
			info.root,
			format_size_human(info.total),
			format_size_human(used),
			format_size_human(info.avail),
			use_pct,
		))
	} else {
		winconsole.write_string(out, fmt.tprintf("%-16s %12s %12s %12s %3d%%\r\n",
			info.root,
			format_size_1k(info.total),
			format_size_1k(used),
			format_size_1k(info.avail),
			use_pct,
		))
	}
}

main :: proc() {
	human, help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'h', long = "human-readable", kind = .Bool_Last_Wins, target = &human,   value_if_set = true},
			{long  = "help",                       kind = .Bool_Last_Wins, target = &help,    value_if_set = true},
			{long  = "version",                    kind = .Bool_Last_Wins, target = &version, value_if_set = true},
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

	print_header(out, human)
	exit_code := 0

	if len(parsed.rest) == 0 {
		disks := all_local_disks()
		defer delete(disks)
		for info in disks {
			print_disk(out, info, human)
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
			print_disk(out, info, human)
		}
	}

	os.exit(exit_code)
}
