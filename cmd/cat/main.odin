package main

import "core:os"
import win "core:sys/windows"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winio"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: cat [OPTION]... [FILE]...
Concatenate FILE(s) to standard output.

With no FILE, or when FILE is -, read standard input.

  -A, --show-all          equivalent to -vET
  -b, --number-nonblank   number nonempty output lines, overrides -n
  -e                      equivalent to -vE
  -E, --show-ends         display $ at end of each line
  -n, --number            number all output lines
  -s, --squeeze-blank     suppress repeated empty output lines
  -t                      equivalent to -vT
  -T, --show-tabs         display TAB characters as ^I
  -u                      (ignored)
  -v, --show-nonprinting  use ^ and M- notation, except for LFD and TAB
      --help              display this help and exit
      --version           output version information and exit
`

main :: proc() {
	help, version: bool
	opts_number, opts_number_nonblank, opts_squeeze: bool
	opts_ends, opts_tabs, opts_nonprinting: bool
	show_all, show_ends_v, show_tabs_v, no_buf: bool

	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{long = "help",    kind = .Bool_Last_Wins, target = &help,    value_if_set = true},
			{long = "version", kind = .Bool_Last_Wins, target = &version, value_if_set = true},
			{long = "number-nonblank", short = 'b', kind = .Bool_Last_Wins, target = &opts_number_nonblank, value_if_set = true},
			{long = "number", short = 'n', kind = .Bool_Last_Wins, target = &opts_number, value_if_set = true},
			{long = "squeeze-blank", short = 's', kind = .Bool_Last_Wins, target = &opts_squeeze, value_if_set = true},
			{long = "show-ends", short = 'E', kind = .Bool_Last_Wins, target = &opts_ends, value_if_set = true},
			{long = "show-tabs", short = 'T', kind = .Bool_Last_Wins, target = &opts_tabs, value_if_set = true},
			{long = "show-nonprinting", short = 'v', kind = .Bool_Last_Wins, target = &opts_nonprinting, value_if_set = true},
			{long = "show-all", short = 'A', kind = .Bool_Last_Wins, target = &show_all, value_if_set = true},
			{short = 'e', kind = .Bool_Last_Wins, target = &show_ends_v, value_if_set = true},
			{short = 't', kind = .Bool_Last_Wins, target = &show_tabs_v, value_if_set = true},
			{long = "u", short = 'u', kind = .Bool_Last_Wins, target = &no_buf, value_if_set = true},
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
		winconsole.write_string(out, "cat (winix) " + VERSION + "\r\n")
		os.exit(0)
	}

	opts := Cat_Options{
		number =           opts_number,
		number_nonblank =  opts_number_nonblank,
		squeeze_blank =    opts_squeeze,
		show_ends =        opts_ends || show_ends_v || show_all,
		show_tabs =        opts_tabs || show_tabs_v || show_all,
		show_nonprinting = opts_nonprinting || show_ends_v || show_tabs_v || show_all,
	}
	_ = no_buf

	if len(parsed.rest) == 0 {
		h := win.GetStdHandle(win.STD_INPUT_HANDLE)
		if win.GetFileType(h) != win.FILE_TYPE_CHAR {
			if err := write_stdin_to_stdout(opts); err != .None {
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
		err := write_file_to_stdout(path, opts)
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