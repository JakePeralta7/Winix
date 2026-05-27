package main

import "core:fmt"
import "core:os"
import win "core:sys/windows"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winio"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: grep [-i] [-n] [-l] [-v] [-c] [-r] [--help] [--version] PATTERN [file ...]
Search for PATTERN in each file (fixed-string, not a regular expression).

  -i, --ignore-case        case-insensitive matching
  -n, --line-number        prefix matching lines with their line number
  -l, --files-with-matches print only the names of files with matches
  -v, --invert-match       select non-matching lines
  -c, --count              print only a count of matching lines per file
  -r, --recursive          search directories recursively
  --help                   print this message and exit
  --version                print version and exit

Exit status is 0 if any line matched, 1 if no match was found, 2 on error.
`

// print_match emits one matched line to out with the appropriate prefix.
print_match :: proc(out: winconsole.Writer, m: Line_Match, show_filename: bool, filename: string, show_line_num: bool) {
	if show_filename {
		winconsole.write_string(out, filename)
		winconsole.write_string(out, ":")
	}
	if show_line_num {
		winconsole.write_string(out, fmt.tprintf("%d:", m.line_num))
	}
	winconsole.write_string(out, m.line)
	winconsole.write_string(out, "\r\n")
}

// search_one searches path and returns (match_count, error).
// It writes output directly to out/errw according to mode flags.
search_one :: proc(
	out, errw:        winconsole.Writer,
	path:             string,
	pattern:          string,
	opts:             Match_Opts,
	show_filename:    bool,
	show_line_num:    bool,
	files_only:       bool,
	count_only:       bool,
) -> (match_count: int, had_error: bool) {
	fh, ferr := winio.open_file_for_read(path)
	if ferr != .None {
		winconsole.write_string(errw, "grep: ")
		winconsole.write_string(errw, path)
		winconsole.write_string(errw, ": ")
		#partial switch ferr {
		case .Not_Found:     winconsole.write_string(errw, "no such file or directory")
		case .Is_Directory:  winconsole.write_string(errw, "is a directory")
		case .Access_Denied: winconsole.write_string(errw, "permission denied")
		case:                winconsole.write_string(errw, "open failed")
		}
		winconsole.write_string(errw, "\r\n")
		return 0, true
	}

	data := read_all(fh)
	win.CloseHandle(fh)
	defer delete(data)

	matches := grep_bytes(string(data), pattern, opts)
	defer delete(matches)

	match_count = len(matches)

	if count_only {
		if show_filename {
			winconsole.write_string(out, path)
			winconsole.write_string(out, ":")
		}
		winconsole.write_string(out, fmt.tprintf("%d\r\n", match_count))
		return
	}

	if files_only {
		if match_count > 0 {
			winconsole.write_line(out, path)
		}
		return
	}

	for m in matches {
		print_match(out, m, show_filename, path, show_line_num)
	}
	return
}

main :: proc() {
	ignore_case, line_num, files_only, invert, count_only, recursive, help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'i', long = "ignore-case",        kind = .Bool_Last_Wins, target = &ignore_case, value_if_set = true},
			{short = 'n', long = "line-number",        kind = .Bool_Last_Wins, target = &line_num,    value_if_set = true},
			{short = 'l', long = "files-with-matches", kind = .Bool_Last_Wins, target = &files_only,  value_if_set = true},
			{short = 'v', long = "invert-match",       kind = .Bool_Last_Wins, target = &invert,      value_if_set = true},
			{short = 'c', long = "count",              kind = .Bool_Last_Wins, target = &count_only,  value_if_set = true},
			{short = 'r', long = "recursive",          kind = .Bool_Last_Wins, target = &recursive,   value_if_set = true},
			{long  = "help",                           kind = .Bool_Last_Wins, target = &help,        value_if_set = true},
			{long  = "version",                        kind = .Bool_Last_Wins, target = &version,     value_if_set = true},
		},
	}

	args := os.args[1:] if len(os.args) > 1 else []string{}
	parsed, perr, tok := cliflag.parse(args, spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "grep: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'grep --help'.\r\n")
		os.exit(2)
	}
	if help    { winconsole.write_string(out, USAGE); os.exit(0) }
	if version { winconsole.write_line(out, "grep (winix) " + VERSION); os.exit(0) }

	if len(parsed.rest) == 0 {
		winconsole.write_string(errw, "grep: missing PATTERN\r\nTry 'grep --help'.\r\n")
		os.exit(2)
	}

	pattern    := parsed.rest[0]
	file_args  := parsed.rest[1:]
	opts       := Match_Opts{ignore_case = ignore_case, invert = invert}

	// Resolve files: expand directories if -r, warn otherwise.
	files := make([dynamic]string)
	dir_expanded := make([dynamic]string) // paths allocated by collect_files – freed at end

	if len(file_args) == 0 {
		// No file arguments: read from stdin if it is piped.
		h := win.GetStdHandle(win.STD_INPUT_HANDLE)
		if win.GetFileType(h) != win.FILE_TYPE_CHAR {
			data    := read_all(h)
			matches := grep_bytes(string(data), pattern, opts)
			n       := len(matches)
			if count_only {
				winconsole.write_string(out, fmt.tprintf("%d\r\n", n))
			} else {
				for m in matches {
					if line_num {
						winconsole.write_string(out, fmt.tprintf("%d:", m.line_num))
					}
					winconsole.write_string(out, m.line)
					winconsole.write_string(out, "\r\n")
				}
			}
			delete(matches)
			delete(data)
			os.exit(0 if n > 0 else 1)
		}
		winconsole.write_string(errw, "grep: missing PATTERN and no files\r\nTry 'grep --help'.\r\n")
		os.exit(2)
	}

	// Build the effective file list, expanding directories when -r.
	for path in file_args {
		wpath := win.utf8_to_wstring(path, context.temp_allocator)
		attrs := win.GetFileAttributesW(wpath)
		if attrs != winio.INVALID_FILE_ATTRS && attrs & win.FILE_ATTRIBUTE_DIRECTORY != 0 {
			if recursive {
				before := len(dir_expanded)
				collect_files(path, &dir_expanded)
				for p in dir_expanded[before:] {
					append(&files, p)
				}
			} else {
				winconsole.write_string(errw, "grep: ")
				winconsole.write_string(errw, path)
				winconsole.write_string(errw, ": is a directory\r\n")
			}
		} else {
			append(&files, path)
		}
	}

	show_filename := len(files) > 1
	any_match     := false
	had_error     := false

	for path in files {
		mc, err := search_one(out, errw, path, pattern, opts, show_filename, line_num, files_only, count_only)
		if err  { had_error = true }
		if mc > 0 { any_match = true }
	}

	if had_error { os.exit(2) }
	os.exit(0 if any_match else 1)
}
