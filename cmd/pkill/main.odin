package main

import "core:fmt"
import "core:os"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: pkill [-x] [-n] [-v] [--help] [--version] pattern ...
Kill processes by name pattern.

  -x, --exact    pattern must match the full process name (e.g. notepad.exe)
  -n, --dry-run  show what would be killed without killing
  -v, --verbose  print each killed process
  --help         print this message and exit
  --version      print version and exit

Note: on Windows all process termination is unconditional (no signal support).
Exit status is 0 if at least one process matched, 1 if no processes were found.
`

main :: proc() {
	exact, dry_run, verbose, help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'x', long = "exact",   kind = .Bool_Last_Wins, target = &exact,   value_if_set = true},
			{short = 'n', long = "dry-run", kind = .Bool_Last_Wins, target = &dry_run, value_if_set = true},
			{short = 'v', long = "verbose", kind = .Bool_Last_Wins, target = &verbose, value_if_set = true},
			{long  = "help",                kind = .Bool_Last_Wins, target = &help,    value_if_set = true},
			{long  = "version",             kind = .Bool_Last_Wins, target = &version, value_if_set = true},
		},
	}

	args := os.args[1:] if len(os.args) > 1 else []string{}
	parsed, perr, tok := cliflag.parse(args, spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "pkill: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'pkill --help'.\r\n")
		os.exit(2)
	}
	if help {
		winconsole.write_string(out, USAGE)
		os.exit(0)
	}
	if version {
		winconsole.write_line(out, "pkill (winix) " + VERSION)
		os.exit(0)
	}
	patterns := parsed.rest

	if len(patterns) == 0 {
		if stdin_lines := winconsole.read_stdin_lines(); stdin_lines != nil {
			patterns = stdin_lines
		}
	}

	if len(patterns) == 0 {
		winconsole.write_string(errw, "pkill: missing operand\r\nTry 'pkill --help'.\r\n")
		os.exit(1)
	}

	// -n implies -v: always show what would be killed in dry-run mode
	if dry_run {
		verbose = true
	}

	opts   := Match_Opts{exact = exact, dry_run = dry_run}
	action := "would kill" if dry_run else "killed"

	any_matched := false
	for pattern in patterns {
		results, rerr := kill_by_name(pattern, opts)
		defer free_results(results)

		if rerr == .Snapshot_Failed {
			winconsole.write_string(errw, "pkill: cannot enumerate processes\r\n")
			os.exit(2)
		}

		if len(results) == 0 {
			winconsole.write_string(errw, "pkill: no process found: ")
			winconsole.write_string(errw, pattern)
			winconsole.write_string(errw, "\r\n")
			continue
		}

		any_matched = true

		for r in results {
			if verbose {
				winconsole.write_string(out, fmt.tprintf("pkill: %s: %s (PID %d)\r\n", action, r.name, r.pid))
			}
			switch r.err {
			case .Access_Denied:
				winconsole.write_string(errw, fmt.tprintf("pkill: %s: access denied\r\n", r.name))
			case .Kill_Failed:
				winconsole.write_string(errw, fmt.tprintf("pkill: %s: kill failed\r\n", r.name))
			case .None, .Snapshot_Failed:
				// nothing to report
			}
		}
	}

	os.exit(0 if any_matched else 1)
}
