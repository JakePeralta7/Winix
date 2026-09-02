package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winio"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: ls [OPTION]... [FILE]...
List information about the FILEs (the current directory by default).

  -a, --all                  do not ignore entries starting with .
  -l                         use a long listing format
  -h, --human-readable       with -l: print sizes in human readable format
  -r, --reverse              reverse order while sorting
  -R, --recursive            list subdirectories recursively
  -S                         sort by file size, largest first
  -t                         sort by modification time, newest first
  -1                         list one file per line
      --color[=WHEN]         colorize the output (when: always|auto|never)
      --help                 display this help and exit
      --version              output version information and exit
`

main :: proc() {
	long_fmt, all, one_line, human, reverse, recursive, sort_time, sort_size, help, version: bool
	color: [dynamic]string
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'a', long = "all",           kind = .Bool_Last_Wins, target = &all,        value_if_set = true},
			{short = 'l',                         kind = .Bool_Last_Wins, target = &long_fmt,   value_if_set = true},
			{short = 'h', long = "human-readable", kind = .Bool_Last_Wins, target = &human,     value_if_set = true},
			{short = 'r', long = "reverse",       kind = .Bool_Last_Wins, target = &reverse,    value_if_set = true},
			{short = 'R', long = "recursive",     kind = .Bool_Last_Wins, target = &recursive,  value_if_set = true},
			{short = 'S',                         kind = .Bool_Last_Wins, target = &sort_size,  value_if_set = true},
			{short = 't',                         kind = .Bool_Last_Wins, target = &sort_time,  value_if_set = true},
			{short = '1',                         kind = .Bool_Last_Wins, target = &one_line,   value_if_set = true},
			{short = 'H', long = "dereference-command-line", kind = .Bool_Last_Wins, target = &one_line, value_if_set = true},
			{             long = "color",       kind = .Value_Optional, values = &color},
			{             long = "help",        kind = .Bool_Last_Wins, target = &help,         value_if_set = true},
			{             long = "version",     kind = .Bool_Last_Wins, target = &version,      value_if_set = true},
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

	color_on := false
	if len(color) > 0 {
		mode := color[len(color)-1]
		switch mode {
		case "always", "yes", "force":
			color_on = true
		case "auto", "tty":
			color_on = out.is_console
		case "never", "no":
			color_on = false
		}
	}

	paths := parsed.rest
	if len(paths) == 0 {
		paths = []string{"."}
	}

	opts := Ls_Opts{
		long        = long_fmt,
		all         = all,
		one_line    = one_line,
		human       = human,
		reverse     = reverse,
		color       = color_on,
		sort_time   = sort_time,
		sort_size   = sort_size,
	}

	// Recursion handles printing headers internally, so operate per top operand.
	exit_code := 0
	multiple := len(paths) > 1

	if recursive {
		for path, i in paths {
			if multiple && i > 0 {
				winconsole.write_string(out, "\r\n")
			}
			code := list_recursive(out, errw, path, opts, first_header = (i == 0 || multiple))
			if code != 0 { exit_code = 1 }
		}
		os.exit(exit_code)
	}

	for path, i in paths {
		if multiple {
			if i > 0 {
				winconsole.write_string(out, "\r\n")
			}
			winconsole.write_string(out, path)
			winconsole.write_string(out, ":\r\n")
		}

		code := list_one(out, errw, path, opts)
		if code != 0 { exit_code = 1 }
	}

	os.exit(exit_code)
}

// Ls_Opts bundles the sorting/formatting flags passed through recursion.
Ls_Opts :: struct {
	long:      bool,
	all:       bool,
	one_line:  bool,
	human:     bool,
	reverse:   bool,
	color:     bool,
	sort_time: bool,
	sort_size: bool,
}

// list_recursive lists path and, when -R, all subdirectories depth-first.
list_recursive :: proc(out, errw: winconsole.Writer, path: string, opts: Ls_Opts, first_header := false) -> int {
	// Determine if path is a directory.
	dir_info, is_dir := head_stat(path)

	if !is_dir {
		// A single file operand: print its entry line.
		if e, ok := stat_one(path); ok {
			defer free_entries([]Entry{e})
			print_entries(out, []Entry{e}, opts)
			return 0
		}
		report_denied(errw, path)
		return 1
	}

	entries, lerr := list_dir(path, opts.all)
	if lerr != .None {
		report_denied(errw, path)
		return 1
	}
	defer free_entries(entries)

	// Always show a header for recursive listing.
	winconsole.write_string(out, path)
	winconsole.write_string(out, ":\r\n")

	sort_entries(entries, opts)

	// Non-directory printable entries first.
	dirs: [dynamic]Entry
	defer delete(dirs)

	visible: [dynamic]Entry
	defer delete(visible)

	for e in entries {
		if e.is_dir && !e.is_reparse {
			append(&dirs, e)
		} else {
			append(&visible, e)
		}
	}

	print_entries(out, visible[:], opts)
	if len(visible) > 0 && len(dirs) > 0 {
		winconsole.write_string(out, "\r\n")
	}

	// Recurse into subdirectories (excluding . and ..).
	exit_code := 0
	for d in dirs {
		if d.name == "." || d.name == ".." { continue }
		winconsole.write_string(out, "\r\n")
		code := list_recursive(out, errw, d.path, opts)
		if code != 0 { exit_code = 1 }
	}
	return exit_code
}

// list_one lists a single operand path (a directory or, with -l, a file).
list_one :: proc(out, errw: winconsole.Writer, path: string, opts: Ls_Opts) -> int {
	if e, ok := stat_one(path); ok && !e.is_dir {
		// Single non-directory operand: print its line.
		defer free_entries([]Entry{e})
		print_entries(out, []Entry{e}, opts)
		return 0
	}

	entries, lerr := list_dir(path, opts.all)
	if lerr != .None {
		report_denied(errw, path)
		return 1
	}
	defer free_entries(entries)

	sort_entries(entries, opts)
	print_entries(out, entries, opts)
	return 0
}

// head_stat reports whether path is an existing directory (or missing).
head_stat :: proc(path: string) -> (bool, bool) {
	return winio.is_directory(path), true
}

report_denied :: proc(errw: winconsole.Writer, path: string) {
	winconsole.write_string(errw, "ls: cannot access '")
	winconsole.write_string(errw, path)
	winconsole.write_string(errw, "': No such file or directory\r\n")
}

// sort_entries orders entries per the requested sort flags.
sort_entries :: proc(entries: []Entry, opts: Ls_Opts) {
	sort_mode = {time = opts.sort_time, size = opts.sort_size, reverse = opts.reverse}
	slice.sort_by(entries, entry_cmp)
}

// Package-level sort mode consulted by entry_cmp. We avoid closures here
// because Odin does not capture locals inside nested anonymous procs.
@(private)
sort_mode := struct {
	time:    bool,
	size:    bool,
	reverse: bool,
}{}

@(private)
entry_cmp :: proc(a, b: Entry) -> bool {
	less: bool
	if sort_mode.time {
		// -t: newest first (descending by time).
		less = cmp_time(a, b) > 0
	} else if sort_mode.size {
		// -S: largest first (descending by size).
		less = a.size > b.size
	} else {
		less = name_less(a.name, b.name)
	}
	if sort_mode.reverse {
		return !less
	}
	return less
}

@(private)
cmp_time :: proc(a, b: Entry) -> int {
	// Returns >0 when a is newer than b.
	if a.year != b.year { return int(a.year) - int(b.year) }
	if a.month != b.month { return int(a.month) - int(b.month) }
	if a.day != b.day { return int(a.day) - int(b.day) }
	if a.hour != b.hour { return int(a.hour) - int(b.hour) }
	if a.minute != b.minute { return int(a.minute) - int(b.minute) }
	return 0
}

@(private)
name_less :: proc(a, b: string) -> bool {
	al := strings.to_lower(a, context.temp_allocator)
	bl := strings.to_lower(b, context.temp_allocator)
	return strings.compare(al, bl) < 0
}

// print_entries writes entries to out in long or short format.
print_entries :: proc(out: winconsole.Writer, entries: []Entry, opts: Ls_Opts) {
	if opts.long {
		print_long(out, entries, opts)
	} else {
		print_short(out, entries, opts)
	}
}

print_short :: proc(out: winconsole.Writer, entries: []Entry, opts: Ls_Opts) {
	for e in entries {
		write_colored(out, e, opts.color)
		winconsole.write_string(out, "\r\n")
	}
}

print_long :: proc(out: winconsole.Writer, entries: []Entry, opts: Ls_Opts) {
	// Compute max size column width for right-alignment
	max_size_w := 1
	for e in entries {
		w := len(fmt_size(e.size, opts.human))
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
		size_str := fmt_size(e.size, opts.human)
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
		write_colored(out, e, opts.color)
		winconsole.write_string(out, "\r\n")
	}
}

// fmt_size renders e.size in human-readable form when human is true.
fmt_size :: proc(size: u64, human: bool) -> string {
	if !human {
		return fmt.tprintf("%d", size)
	}
	const_units := [?]string{"B", "K", "M", "G", "T", "P"}
	if size < 1024 {
		return fmt.tprintf("%d", size)
	}
	f := f64(size)
	unit := 0
	for f >= 1024 && unit < len(const_units)-1 {
		f /= 1024
		unit += 1
	}
	if f >= 10 {
		return fmt.tprintf("%.0f%c", f, const_units[unit][0])
	}
	return fmt.tprintf("%.1f%c", f, const_units[unit][0])
}

// write_colored writes the entry name, optionally wrapping it in ANSI color
// codes based on its type.
write_colored :: proc(out: winconsole.Writer, e: Entry, color: bool) {
	if !color {
		winconsole.write_string(out, e.name)
		return
	}
	code := ansi_for(e)
	if code == "" {
		winconsole.write_string(out, e.name)
		return
	}
	winconsole.write_string(out, "\x1b[")
	winconsole.write_string(out, code)
	winconsole.write_string(out, "m")
	winconsole.write_string(out, e.name)
	winconsole.write_string(out, "\x1b[0m")
}

@(private)
ansi_for :: proc(e: Entry) -> string {
	if e.is_dir && !e.is_reparse {
		return "34" // blue
	}
	if e.is_reparse {
		return "36" // cyan
	}
	if e.is_readonly {
		return "33" // yellow
	}
	if is_executable(e.name) {
		return "32" // green
	}
	return ""
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