package main

import "core:os"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: touch [--help] [--version] file ...
Update the access and modification timestamps of each file.
Create the file if it does not exist.

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

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "touch: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'touch --help'.\r\n")
		os.exit(2)
	}
	if help {
		winconsole.write_string(out, USAGE)
		os.exit(0)
	}
	if version {
		winconsole.write_line(out, "touch (winix) " + VERSION)
		os.exit(0)
	}
	paths := parsed.rest

	if len(paths) == 0 {
		if stdin_lines := winconsole.read_stdin_lines(); stdin_lines != nil {
			paths = stdin_lines
		}
	}

	if len(paths) == 0 {
		winconsole.write_string(errw, "touch: missing operand\r\nTry 'touch --help'.\r\n")
		os.exit(1)
	}

	exit_code := 0
	for path in paths {
		err := touch(path)
		if err == .None { continue }
		report_error(errw, path, err)
		exit_code = 1
	}
	os.exit(exit_code)
}

report_error :: proc(errw: winconsole.Writer, path: string, err: Error) {
	winconsole.write_string(errw, "touch: cannot touch '")
	winconsole.write_string(errw, path)
	winconsole.write_string(errw, "': ")
	winconsole.write_string(errw, message_for(err))
	winconsole.write_string(errw, "\r\n")
}

message_for :: proc(err: Error) -> string {
	switch err {
	case .None:         return ""
	case .Is_Directory: return "Is a directory"
	case .Access_Denied: return "Permission denied"
	case .Touch_Failed: return "operation failed"
	}
	return "unknown error"
}
