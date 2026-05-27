package main

import "core:fmt"
import "core:os"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: ps [--help] [--version]
List currently running processes.

  --help     print this message and exit
  --version  print version and exit
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
	_, perr, tok := cliflag.parse(args, spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "ps: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'ps --help'.\r\n")
		os.exit(2)
	}
	if help    { winconsole.write_string(out, USAGE); os.exit(0) }
	if version { winconsole.write_line(out, "ps (winix) " + VERSION); os.exit(0) }

	procs, ok := list_processes()
	if !ok {
		winconsole.write_string(errw, "ps: failed to enumerate processes\r\n")
		os.exit(1)
	}
	defer free_proc_list(procs)

	winconsole.write_string(out, fmt.tprintf("%6s %6s  %s\r\n", "PID", "PPID", "Name"))
	for p in procs {
		winconsole.write_string(out, fmt.tprintf("%6d %6d  %s\r\n", p.pid, p.ppid, p.name))
	}
}
