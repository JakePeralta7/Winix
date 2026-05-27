package main

import "core:os"
import "core:strconv"
import win "core:sys/windows"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winio"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: head [-n COUNT] [--help] [--version] file ...
Print the first 10 lines of each file to standard output.

  -n COUNT, --lines COUNT  print the first COUNT lines (default 10)
  --help                   print this message and exit
  --version                print version and exit
`

DEFAULT_LINES :: 10

main :: proc() {
	raw_args := os.args[1:] if len(os.args) > 1 else []string{}
	out  := winconsole.stdout()
	errw := winconsole.stderr()

	// Pre-process: extract -n / --lines count before passing to cliflag.
	line_count := DEFAULT_LINES
	filtered := make([dynamic]string, 0, len(raw_args), context.temp_allocator)
	i := 0
	for i < len(raw_args) {
		arg := raw_args[i]
		if arg == "-n" || arg == "--lines" {
			i += 1
			if i >= len(raw_args) {
				winconsole.write_string(errw, "head: option requires an argument -- 'n'\r\nTry 'head --help'.\r\n")
				os.exit(2)
			}
			n, ok := strconv.parse_int(raw_args[i], 10)
			if !ok || n < 0 {
				winconsole.write_string(errw, "head: invalid number of lines: '")
				winconsole.write_string(errw, raw_args[i])
				winconsole.write_string(errw, "'\r\nTry 'head --help'.\r\n")
				os.exit(2)
			}
			line_count = n
		} else if len(arg) > 2 && arg[0] == '-' && arg[1] == 'n' {
			n, ok := strconv.parse_int(arg[2:], 10)
			if !ok || n < 0 {
				winconsole.write_string(errw, "head: invalid number of lines: '")
				winconsole.write_string(errw, arg[2:])
				winconsole.write_string(errw, "'\r\nTry 'head --help'.\r\n")
				os.exit(2)
			}
			line_count = n
		} else {
			append(&filtered, arg)
		}
		i += 1
	}

	help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{long = "help",    kind = .Bool_Last_Wins, target = &help,    value_if_set = true},
			{long = "version", kind = .Bool_Last_Wins, target = &version, value_if_set = true},
		},
	}

	parsed, perr, tok := cliflag.parse(filtered[:], spec)
	if perr != .None {
		winconsole.write_string(errw, "head: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'head --help'.\r\n")
		os.exit(2)
	}
	if help {
		winconsole.write_string(out, USAGE)
		os.exit(0)
	}
	if version {
		winconsole.write_line(out, "head (winix) " + VERSION)
		os.exit(0)
	}
	if len(parsed.rest) == 0 {
		h := win.GetStdHandle(win.STD_INPUT_HANDLE)
		if win.GetFileType(h) != win.FILE_TYPE_CHAR {
			if err := write_head_from_stdin(line_count); err != .None {
				winconsole.write_string(errw, "head: error reading stdin\r\n")
				os.exit(1)
			}
			os.exit(0)
		}
		winconsole.write_string(errw, "head: missing operand\r\nTry 'head --help'.\r\n")
		os.exit(1)
	}

	print_headers := len(parsed.rest) > 1
	exit_code := 0
	for path, idx in parsed.rest {
		if print_headers {
			if idx > 0 {
				winconsole.write_string(out, "\r\n")
			}
			winconsole.write_string(out, "==> ")
			winconsole.write_string(out, path)
			winconsole.write_string(out, " <==\r\n")
		}
		err := write_head(path, line_count)
		if err == .None { continue }
		report_error(errw, path, err)
		exit_code = 1
	}
	os.exit(exit_code)
}

report_error :: proc(errw: winconsole.Writer, path: string, err: winio.Error) {
	winconsole.write_string(errw, "head: ")
	winconsole.write_string(errw, path)
	winconsole.write_string(errw, ": ")
	winconsole.write_string(errw, message_for(err))
	winconsole.write_string(errw, "\r\n")
}

message_for :: proc(err: winio.Error) -> string {
	switch err {
	case .None:          return ""
	case .Not_Found:     return "No such file or directory"
	case .Is_Directory:  return "Is a directory"
	case .Access_Denied: return "Permission denied"
	case .Open_Failed:   return "cannot open file"
	case .Read_Failed:   return "cannot read file"
	case .Write_Failed:  return "cannot write output"
	}
	return "unknown error"
}
