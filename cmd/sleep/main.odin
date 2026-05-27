package main

import "core:os"
import "core:strconv"
import win "core:sys/windows"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: sleep DURATION [DURATION ...]
Pause for the total of the given durations in seconds.

  DURATION  a non-negative number (decimals allowed, e.g. 0.5)
  --help    print this message and exit
  --version print version and exit
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
		winconsole.write_string(errw, "sleep: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'sleep --help'.\r\n")
		os.exit(2)
	}
	if help {
		winconsole.write_string(out, USAGE)
		os.exit(0)
	}
	if version {
		winconsole.write_line(out, "sleep (winix) " + VERSION)
		os.exit(0)
	}
	if len(parsed.rest) == 0 {
		winconsole.write_string(errw, "sleep: missing operand\r\nTry 'sleep --help'.\r\n")
		os.exit(1)
	}

	total_ms: f64 = 0
	for s in parsed.rest {
		v, ok := strconv.parse_f64(s)
		if !ok || v < 0 {
			winconsole.write_string(errw, "sleep: invalid time interval: '")
			winconsole.write_string(errw, s)
			winconsole.write_string(errw, "'\r\n")
			os.exit(1)
		}
		total_ms += v * 1000.0
	}

	win.Sleep(win.DWORD(total_ms))
}
