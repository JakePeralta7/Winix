package main

import "core:fmt"
import "core:os"
import "core:strconv"
import win "core:sys/windows"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winio"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: uniq [OPTION]... [FILE]
Filter adjacent matching lines from input.

  -c, --count            prefix lines by the number of occurrences
  -d, --repeated         only print lines that appear more than once
  -u, --unique           only print lines that appear exactly once
  -i, --ignore-case      ignore differences in case when comparing
  -f, --skip-fields=N    skip first N whitespace-separated fields
  -s, --skip-chars=N     skip first N characters
  -w, --check-chars=N    compare only first N characters
  -z, --zero-terminated  line delimiter is NUL, not newline
      --help             print this message and exit
      --version          output version information and exit

With no FILE, or when FILE is -, read standard input.
`

main :: proc() {
	count_flag, repeated, unique_flag, ignore_case, help, version: bool
	zero_term: bool
	skip_fields_vals, skip_chars_vals, check_chars_vals: [dynamic]string
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'c', long = "count",           kind = .Bool_Last_Wins, target = &count_flag,  value_if_set = true},
			{short = 'd', long = "repeated",        kind = .Bool_Last_Wins, target = &repeated,    value_if_set = true},
			{short = 'u', long = "unique",          kind = .Bool_Last_Wins, target = &unique_flag, value_if_set = true},
			{short = 'i', long = "ignore-case",     kind = .Bool_Last_Wins, target = &ignore_case, value_if_set = true},
			{short = 'z', long = "zero-terminated", kind = .Bool_Last_Wins, target = &zero_term,   value_if_set = true},
			{short = 'f', long = "skip-fields",     kind = .Value_Next, values = &skip_fields_vals},
			{short = 's', long = "skip-chars",      kind = .Value_Next, values = &skip_chars_vals},
			{short = 'w', long = "check-chars",     kind = .Value_Next, values = &check_chars_vals},
			{             long = "help",            kind = .Bool_Last_Wins, target = &help,        value_if_set = true},
			{             long = "version",         kind = .Bool_Last_Wins, target = &version,     value_if_set = true},
		},
	}

	args := os.args[1:] if len(os.args) > 1 else []string{}
	parsed, perr, tok := cliflag.parse(args, spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "uniq: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'uniq --help'.\r\n")
		os.exit(2)
	}
	if help    { winconsole.write_string(out, USAGE); os.exit(0) }
	if version { winconsole.write_string(out, "uniq (winix) " + VERSION + "\r\n"); os.exit(0) }

	files := parsed.rest
	if len(files) > 1 {
		winconsole.write_string(errw, "uniq: extra operand '")
		winconsole.write_string(errw, files[1])
		winconsole.write_string(errw, "'\r\nTry 'uniq --help'.\r\n")
		os.exit(2)
	}

	// Parse numeric options.
	skip_fields := 0
	skip_chars := 0
	check_chars := -1  // -1 means no limit
	
	if len(skip_fields_vals) > 0 {
		v, ok := strconv.parse_int(skip_fields_vals[len(skip_fields_vals)-1])
		if !ok || v < 0 {
			winconsole.write_string(errw, "uniq: invalid skip-fields value\r\n")
			os.exit(2)
		}
		skip_fields = v
	}
	if len(skip_chars_vals) > 0 {
		v, ok := strconv.parse_int(skip_chars_vals[len(skip_chars_vals)-1])
		if !ok || v < 0 {
			winconsole.write_string(errw, "uniq: invalid skip-chars value\r\n")
			os.exit(2)
		}
		skip_chars = v
	}
	if len(check_chars_vals) > 0 {
		v, ok := strconv.parse_int(check_chars_vals[len(check_chars_vals)-1])
		if !ok || v < 0 {
			winconsole.write_string(errw, "uniq: invalid check-chars value\r\n")
			os.exit(2)
		}
		check_chars = v
	}

	raw: []u8
	if len(files) == 0 {
		h   := win.GetStdHandle(win.STD_INPUT_HANDLE)
		raw  = read_all(h)
	} else {
		fh, err := winio.open_file_for_read(files[0])
		if err != .None {
			winconsole.write_string(errw, "uniq: ")
			winconsole.write_string(errw, files[0])
			winconsole.write_string(errw, ": ")
			#partial switch err {
			case .Not_Found:     winconsole.write_string(errw, "no such file or directory")
			case .Is_Directory:  winconsole.write_string(errw, "is a directory")
			case .Access_Denied: winconsole.write_string(errw, "permission denied")
			case:                winconsole.write_string(errw, "open failed")
			}
			winconsole.write_string(errw, "\r\n")
			os.exit(1)
		}
		raw = read_all(fh)
		win.CloseHandle(fh)
	}
	
	delim := u8('\n')
	if zero_term {
		delim = 0
	}

	content := string(raw)
	runs    := collect_runs(content, ignore_case, skip_fields, skip_chars, check_chars, delim)

	for run in runs {
		if repeated   && run.count == 1 { continue }
		if unique_flag && run.count  > 1 { continue }

		if count_flag {
			winconsole.write_string(out, fmt.tprintf("%7d ", run.count))
		}
		winconsole.write_string(out, run.line)
		winconsole.write_string(out, string([]u8{delim}))
	}

	os.exit(0)
}
