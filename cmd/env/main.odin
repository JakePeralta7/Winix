package main

import "core:os"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: env [OPTION]... [NAME=VALUE]... [COMMAND [ARG]...]
Run a program in a modified environment or print the current environment.

  -i, --ignore-environment  start with an empty environment
  -u, --unset=NAME          remove variable from the environment
  -0, --null                end output with NUL instead of newline
      --help                display this help and exit
      --version             output version information and exit

If no COMMAND, print the resulting environment, one NAME=VALUE per line.
`

main :: proc() {
	help, version: bool
	ignore_env, null_term: bool
	unset_vals: [dynamic]string
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'i', long = "ignore-environment", kind = .Bool_Last_Wins, target = &ignore_env, value_if_set = true},
			{short = 'u', long = "unset",             kind = .Value_Next, values = &unset_vals},
			{short = '0', long = "null",              kind = .Bool_Last_Wins, target = &null_term, value_if_set = true},
			{             long = "help",              kind = .Bool_Last_Wins, target = &help,        value_if_set = true},
			{             long = "version",           kind = .Bool_Last_Wins, target = &version,     value_if_set = true},
		},
	}

	raw_args := os.args[1:] if len(os.args) > 1 else []string{}
	exclude  := make([dynamic]string, 0, 4, context.temp_allocator)
	filtered := make([dynamic]string, 0, len(raw_args), context.temp_allocator)
	i := 0
	for i < len(raw_args) {
		arg := raw_args[i]
		if arg == "-u" || arg == "--unset" {
			i += 1
			if i >= len(raw_args) {
				winconsole.write_string(winconsole.stderr(), "env: option requires an argument -- 'u'\r\nTry 'env --help'.\r\n")
				os.exit(2)
			}
			append(&exclude, raw_args[i])
		} else if arg == "-i" || arg == "--ignore-environment" {
			append(&filtered, arg)
		} else {
			append(&filtered, arg)
		}
		i += 1
	}

	parsed, perr, tok := cliflag.parse(filtered[:], spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "env: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'env --help'.\r\n")
		os.exit(2)
	}
	if help    { winconsole.write_string(out, USAGE); os.exit(0) }
	if version { winconsole.write_line(out, "env (winix) " + VERSION); os.exit(0) }

	for v in unset_vals { append(&exclude, v) }

	entries, ok := get_env()
	if !ok {
		winconsole.write_string(errw, "env: failed to read environment\r\n")
		os.exit(1)
	}

	if ignore_env {
		for e in entries { delete(e) }
		delete(entries)
		entries = make([dynamic]string, 0, 0, context.temp_allocator)[:]
	}

	delim := "\r\n"
	if null_term {
		null_bytes := [1]u8{0}
		delim = string(transmute([]u8)(null_bytes[:]))
	}

	for entry in entries {
		if should_exclude(entry, exclude[:]) { continue }
		winconsole.write_string(out, entry)
		winconsole.write_string(out, delim)
	}

	for e in entries { delete(e) }
	delete(entries)
	os.exit(0)
}