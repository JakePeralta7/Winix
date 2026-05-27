package main

import "core:os"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winwhich"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: which [-a] [--help] [--version] name ...
Locate a command by searching PATH.

  -a, --all   print all matching paths, not just the first
  --help      print this message and exit
  --version   print version and exit
`

main :: proc() {
	all, help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'a', long = "all",     kind = .Bool_Last_Wins, target = &all,     value_if_set = true},
			{long  = "help",                kind = .Bool_Last_Wins, target = &help,    value_if_set = true},
			{long  = "version",             kind = .Bool_Last_Wins, target = &version, value_if_set = true},
		},
	}

	args := os.args[1:] if len(os.args) > 1 else []string{}
	parsed, perr, tok := cliflag.parse(args, spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "which: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'which --help'.\r\n")
		os.exit(2)
	}
	if help {
		winconsole.write_string(out, USAGE)
		os.exit(0)
	}
	if version {
		winconsole.write_line(out, "which (winix) " + VERSION)
		os.exit(0)
	}
	if len(parsed.rest) == 0 {
		winconsole.write_string(errw, "which: missing operand\r\nTry 'which --help'.\r\n")
		os.exit(1)
	}

	exit_code := 0
	for name in parsed.rest {
		paths, werr := winwhich.find(name, all)
		defer winwhich.free_results(paths)

		if werr == .Not_Found {
			winconsole.write_string(errw, name)
			winconsole.write_string(errw, " not found\r\n")
			exit_code = 1
			continue
		}

		for p in paths {
			winconsole.write_line(out, p)
		}
	}
	os.exit(exit_code)
}
