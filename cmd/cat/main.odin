package main

import "core:os"
import win "core:sys/windows"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winio"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: cat [--help] [--version] file ...
Concatenate files and print on standard output.

  --help      print this message and exit
  --version   print version and exit
`

main :: proc() {
	help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{long = "help",    kind = .Bool_Last_Wins, target = &help,    value_if_set = true},
			{long = "version", kind = .Bool_Last_Wins, target = &version, value_if_set = true},
		},
	}

	args := os.args[1:] if len(os.args) > 1 else []string{}
	parsed, perr, tok := cliflag.parse(args, spec)

	out := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "cat: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'cat --help'.\r\n")
		os.exit(2)
	}
	if help {
		winconsole.write_string(out, USAGE)
		os.exit(0)
	}
	if version {
		winconsole.write_line(out, "cat (winix) " + VERSION)
		os.exit(0)
	}
	if len(parsed.rest) == 0 {
		h := win.GetStdHandle(win.STD_INPUT_HANDLE)
		if win.GetFileType(h) != win.FILE_TYPE_CHAR {
			if err := write_stdin_to_stdout(); err != .None {
				winconsole.write_string(errw, "cat: error reading stdin\r\n")
				os.exit(1)
			}
			os.exit(0)
		}
		winconsole.write_string(errw, "cat: missing operand\r\nTry 'cat --help'.\r\n")
		os.exit(1)
	}

	exit_code := 0
	for path in parsed.rest {
		err := write_file_to_stdout(path)
		if err == .None { continue }
		report_error(errw, path, err)
		exit_code = 1
	}
	os.exit(exit_code)
}

report_error :: proc(errw: winconsole.Writer, path: string, err: winio.Error) {
	winconsole.write_string(errw, "cat: ")
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
