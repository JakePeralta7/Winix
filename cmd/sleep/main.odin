package main

import "core:os"
import "core:strconv"
import "core:strings"
import win "core:sys/windows"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: sleep NUMBER[SUFFIX]... [--help] [--version]
Pause for the total of the given durations.

  NUMBER may be an integer or floating point.
  SUFFIX may be:
    s - seconds (default)
    m - minutes
    h - hours
    d - days
  --help    display this help and exit
  --version output version information and exit
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
	if help    { winconsole.write_string(out, USAGE); os.exit(0) }
	if version { winconsole.write_line(out, "sleep (winix) " + VERSION); os.exit(0) }

	if len(parsed.rest) == 0 {
		winconsole.write_string(errw, "sleep: missing operand\r\nTry 'sleep --help'.\r\n")
		os.exit(1)
	}

	total_ms: f64 = 0
	for s in parsed.rest {
		ms, ok := parse_duration(s)
		if !ok {
			winconsole.write_string(errw, "sleep: invalid time interval: '")
			winconsole.write_string(errw, s)
			winconsole.write_string(errw, "'\r\n")
			os.exit(1)
		}
		total_ms += ms
	}

	if total_ms > 0xFFFFFFFF {
		winconsole.write_string(errw, "sleep: value too large\r\n")
		os.exit(1)
	}

	win.Sleep(win.DWORD(total_ms))
}

parse_duration :: proc(s: string) -> (f64, bool) {
	if len(s) == 0 { return 0, false }
	
	str := s
	// Check for suffix.
	last := str[len(str)-1]
	multiplier: f64 = 1000.0  // seconds -> milliseconds
	
	if (last >= '0' && last <= '9') {
		// No suffix, default to seconds.
	} else if last == 's' {
		multiplier = 1000.0
		str = str[:len(str)-1]
	} else if last == 'm' {
		multiplier = 60_000.0
		str = str[:len(str)-1]
	} else if last == 'h' {
		multiplier = 3_600_000.0
		str = str[:len(str)-1]
	} else if last == 'd' {
		multiplier = 86_400_000.0
		str = str[:len(str)-1]
	} else {
		return 0, false
	}
	
	if len(str) == 0 { return 0, false }
	
	v, ok := strconv.parse_f64(str)
	if !ok || v < 0 { return 0, false }
	return v * multiplier, true
}