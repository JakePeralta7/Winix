package main

import "core:os"
import "core:strings"
import win "core:sys/windows"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winio"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: sort [OPTION]... [FILE]...
Write sorted concatenation of all FILE(s) to standard output.

  -b, --ignore-leading-blanks  ignore leading blanks
  -c, --check, --check=quiet   check for sorted input; do not sort
  -C, --check=silent           like -c, but do not report first bad line
  -f, --ignore-case            fold lower case to upper case characters
  -g, --general-numeric-sort   compare according to general numerical value
  -n, --numeric-sort           compare according to string numerical value
  -o, --output=FILE            write result to FILE instead of standard output
  -r, --reverse                reverse the result of comparisons
  -u, --unique                 with -c, check for strict ordering; else only
                               the first of an equal run
  -V, --version-sort           natural sort of (version) numbers within text
  -z, --zero-terminated        line delimiter is NUL, not newline
      --help                   display this help and exit
      --version                output version information and exit

With no FILE, or when FILE is -, read standard input.
`

io_error_msg :: proc(err: winio.Error) -> string {
	#partial switch err {
	case .Not_Found:     return "no such file or directory"
	case .Is_Directory:  return "is a directory"
	case .Access_Denied: return "permission denied"
	case .Read_Failed:   return "read error"
	case .Open_Failed:   return "open failed"
	}
	return "error"
}

main :: proc() {
	reverse, unique, numeric, fold_case, help, version: bool
	blanks, general_num, version_sort, check, silent: bool
	zero_term: bool
	output: [dynamic]string
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'r', long = "reverse",             kind = .Bool_Last_Wins, target = &reverse,      value_if_set = true},
			{short = 'u', long = "unique",              kind = .Bool_Last_Wins, target = &unique,       value_if_set = true},
			{short = 'n', long = "numeric-sort",        kind = .Bool_Last_Wins, target = &numeric,      value_if_set = true},
			{short = 'f', long = "ignore-case",         kind = .Bool_Last_Wins, target = &fold_case,    value_if_set = true},
			{short = 'b', long = "ignore-leading-blanks", kind = .Bool_Last_Wins, target = &blanks,     value_if_set = true},
			{short = 'g', long = "general-numeric-sort", kind = .Bool_Last_Wins, target = &general_num, value_if_set = true},
			{short = 'V', long = "version-sort",        kind = .Bool_Last_Wins, target = &version_sort, value_if_set = true},
			{short = 'c', long = "check",               kind = .Bool_Last_Wins, target = &check,        value_if_set = true},
			{short = 'C', long = "check-silent",        kind = .Bool_Last_Wins, target = &silent,       value_if_set = true},
			{short = 'z', long = "zero-terminated",     kind = .Bool_Last_Wins, target = &zero_term,    value_if_set = true},
			{long  = "output", short = 'o',             kind = .Value_Next, values = &output},
			{             long = "help",                kind = .Bool_Last_Wins, target = &help,         value_if_set = true},
			{             long = "version",             kind = .Bool_Last_Wins, target = &version,      value_if_set = true},
		},
	}

	args := os.args[1:] if len(os.args) > 1 else []string{}
	parsed, perr, tok := cliflag.parse(args, spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "sort: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'sort --help'.\r\n")
		os.exit(2)
	}
	if help    { winconsole.write_string(out, USAGE); os.exit(0) }
	if version { winconsole.write_string(out, "sort (winix) " + VERSION + "\r\n"); os.exit(0) }

	files     := parsed.rest
	exit_code := 0

	all_data := make([dynamic]u8, 0, winio.BUF_SIZE)

	if len(files) == 0 {
		h   := win.GetStdHandle(win.STD_INPUT_HANDLE)
		raw := read_all(h)
		append(&all_data, ..raw)
		delete(raw)
	} else {
		for path in files {
			fh, err := winio.open_file_for_read(path)
			if err != .None {
				winconsole.write_string(errw, "sort: ")
				winconsole.write_string(errw, path)
				winconsole.write_string(errw, ": ")
				winconsole.write_string(errw, io_error_msg(err))
				winconsole.write_string(errw, "\r\n")
				exit_code = 1
				continue
			}
			raw := read_all(fh)
			win.CloseHandle(fh)
			append(&all_data, ..raw)
			delete(raw)
		}
	}

	delim := u8('\n')
	if zero_term {
		delim = 0
	}

	content := string(all_data[:])
	lines   := split_to_lines(content, delim)

	if check || silent {
		// Verify the input is already sorted.
		if !is_sorted(lines, numeric, fold_case, blanks, general_num, version_sort) {
			if !silent {
				winconsole.write_string(errw, "sort: input is not sorted\r\n")
			}
			os.exit(1)
		}
		os.exit(exit_code)
	}

	sorted := do_sort(lines, reverse, numeric, fold_case, unique, blanks, general_num, version_sort)

	out_h := win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	owns_out := false
	if out_h == win.INVALID_HANDLE {
		winconsole.write_string(errw, "sort: write error\r\n")
		os.exit(1)
	}
	if len(output) > 0 {
		outpath := win.utf8_to_wstring(output[len(output)-1], context.temp_allocator)
		fh := win.CreateFileW(
			outpath,
			win.GENERIC_WRITE,
			win.FILE_SHARE_READ,
			nil,
			win.CREATE_ALWAYS,
			win.FILE_ATTRIBUTE_NORMAL,
			nil,
		)
		if fh == win.INVALID_HANDLE {
			winconsole.write_string(errw, "sort: cannot open output file '")
			winconsole.write_string(errw, output[len(output)-1])
			winconsole.write_string(errw, "'\r\n")
			os.exit(1)
		}
		out_h = fh
		owns_out = true
	}

	for line in sorted {
		if !winio.write_all(out_h, transmute([]u8)line) {
			winconsole.write_string(errw, "sort: write error\r\n")
			os.exit(1)
		}
		if !winio.write_all(out_h, []u8{delim}) {
			winconsole.write_string(errw, "sort: write error\r\n")
			os.exit(1)
		}
	}

	if owns_out {
		win.CloseHandle(out_h)
	}

	os.exit(exit_code)
}

// is_sorted reports whether lines are in non-decreasing order per the options.
is_sorted :: proc(lines: []string, numeric, fold_case, blanks, general_num, version_sort: bool) -> bool {
	for i in 1..<len(lines) {
		if less(lines[i], lines[i-1], numeric, fold_case, blanks, general_num, version_sort) {
			return false
		}
	}
	return true
}

less :: proc(a, b: string, numeric, fold_case, blanks, general_num, version_sort: bool) -> bool {
	if version_sort {
		return version(a, b)
	}
	if general_num {
		return compare_general_numeric(a, b)
	}
	if numeric {
		return compare_numeric(a, b)
	}
	if fold_case {
		return compare_fold(a, b)
	}
	if blanks {
		return skip_leading_blanks(a) < skip_leading_blanks(b)
	}
	return a < b
}