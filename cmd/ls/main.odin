package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winls"

VERSION :: "0.1.0"

USAGE :: `Usage: ls [-l] [-a] [-1] [--help] [--version] [path ...]
List directory contents.

  -l, --long  long listing format (permissions, size, date)
  -a, --all   include hidden files and . and ..
  -1          list one entry per line
  --help      print this message and exit
  --version   print version and exit
`

main :: proc() {
	long_fmt, all, one_line, help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'l', long = "long",    kind = .Bool_Last_Wins, target = &long_fmt, value_if_set = true},
			{short = 'a', long = "all",     kind = .Bool_Last_Wins, target = &all,      value_if_set = true},
			{short = '1',                   kind = .Bool_Last_Wins, target = &one_line, value_if_set = true},
			{long  = "help",                kind = .Bool_Last_Wins, target = &help,     value_if_set = true},
			{long  = "version",             kind = .Bool_Last_Wins, target = &version,  value_if_set = true},
		},
	}

	args := os.args[1:] if len(os.args) > 1 else []string{}
	parsed, perr, tok := cliflag.parse(args, spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "ls: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'ls --help'.\r\n")
		os.exit(2)
	}
	if help {
		winconsole.write_string(out, USAGE)
		os.exit(0)
	}
	if version {
		winconsole.write_line(out, "ls (winix) " + VERSION)
		os.exit(0)
	}

	paths := parsed.rest
	if len(paths) == 0 {
		paths = []string{"."}
	}

	exit_code := 0
	multiple  := len(paths) > 1

	for path, i in paths {
		if multiple {
			if i > 0 {
				winconsole.write_string(out, "\r\n")
			}
			winconsole.write_string(out, path)
			winconsole.write_string(out, ":\r\n")
		}

		entries, lerr := winls.list_dir(path, all)
		if lerr != .None {
			winconsole.write_string(errw, "ls: cannot access '")
			winconsole.write_string(errw, path)
			winconsole.write_string(errw, "': No such file or directory\r\n")
			exit_code = 1
			continue
		}
		defer winls.free_entries(entries)

		// Sort: . first, .. second, then case-insensitive alpha
		slice.sort_by(entries, proc(a, b: winls.Entry) -> bool {
			if a.name == "." { return true }
			if b.name == "." { return false }
			if a.name == ".." { return true }
			if b.name == ".." { return false }
			al := strings.to_lower(a.name, context.temp_allocator)
			bl := strings.to_lower(b.name, context.temp_allocator)
			return strings.compare(al, bl) < 0
		})

		if long_fmt {
			print_long(out, entries)
		} else {
			print_short(out, entries)
		}
	}

	os.exit(exit_code)
}

print_short :: proc(out: winconsole.Writer, entries: []winls.Entry) {
	for e in entries {
		winconsole.write_string(out, e.name)
		winconsole.write_string(out, "\r\n")
	}
}

print_long :: proc(out: winconsole.Writer, entries: []winls.Entry) {
	// Compute max size column width for right-alignment
	max_size_w := 1
	for e in entries {
		w := digit_count(e.size)
		if w > max_size_w {
			max_size_w = w
		}
	}

	for e in entries {
		// Permissions: type + r + w + x  (4 chars)
		perms: [4]u8
		perms[0] = 'l' if e.is_reparse else ('d' if e.is_dir else '-')
		perms[1] = 'r'
		perms[2] = '-' if e.is_readonly else 'w'
		perms[3] = 'x' if (e.is_dir || e.is_reparse || is_executable(e.name)) else '-'

		// Right-aligned size
		size_str := fmt.tprintf("%d", e.size)
		pad      := max_size_w - len(size_str)

		winconsole.write_string(out, string(perms[:]))
		winconsole.write_string(out, "  ")
		for _ in 0..<pad {
			winconsole.write_string(out, " ")
		}
		winconsole.write_string(out, size_str)
		winconsole.write_string(out, "  ")
		winconsole.write_string(out, fmt.tprintf("%04d-%02d-%02d %02d:%02d",
			e.year, e.month, e.day, e.hour, e.minute))
		winconsole.write_string(out, "  ")
		winconsole.write_string(out, e.name)
		winconsole.write_string(out, "\r\n")
	}
}

is_executable :: proc(name: string) -> bool {
	lower := strings.to_lower(name, context.temp_allocator)
	exts := [?]string{".exe", ".bat", ".cmd", ".com", ".ps1", ".vbs"}
	for ext in exts {
		if strings.has_suffix(lower, ext) {
			return true
		}
	}
	return false
}

digit_count :: proc(n: u64) -> int {
	if n == 0 { return 1 }
	count := 0
	v := n
	for v > 0 {
		count += 1
		v /= 10
	}
	return count
}
