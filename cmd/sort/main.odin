package main

import "core:os"
import win "core:sys/windows"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winio"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: sort [-r] [-u] [-n] [-f] [--help] [--version] [file ...]
Sort lines of text files.

  -r, --reverse       reverse the result of comparisons
  -u, --unique        output only the first of an equal run
  -n, --numeric-sort  compare according to string numerical value
  -f, --ignore-case   fold lower case to upper case characters
  --help              print this message and exit
  --version           print version and exit

With no files reads from stdin.
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
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'r', long = "reverse",      kind = .Bool_Last_Wins, target = &reverse,   value_if_set = true},
			{short = 'u', long = "unique",        kind = .Bool_Last_Wins, target = &unique,    value_if_set = true},
			{short = 'n', long = "numeric-sort",  kind = .Bool_Last_Wins, target = &numeric,   value_if_set = true},
			{short = 'f', long = "ignore-case",   kind = .Bool_Last_Wins, target = &fold_case, value_if_set = true},
			{             long = "help",           kind = .Bool_Last_Wins, target = &help,      value_if_set = true},
			{             long = "version",        kind = .Bool_Last_Wins, target = &version,   value_if_set = true},
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
	if version { winconsole.write_line(out, "sort (winix) " + VERSION); os.exit(0) }

	files     := parsed.rest
	exit_code := 0

	// Accumulate all input bytes (concatenate multiple files).
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

	content := string(all_data[:])
	lines   := split_to_lines(content)
	sorted  := do_sort(lines, reverse, numeric, fold_case, unique)

	for line in sorted {
		winconsole.write_string(out, line)
		winconsole.write_string(out, "\n")
	}

	os.exit(exit_code)
}
