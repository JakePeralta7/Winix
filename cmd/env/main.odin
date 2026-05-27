package main

import "core:os"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: env [-u NAME] [--help] [--version]
Print the current environment, one NAME=VALUE pair per line.

  -u NAME, --unset NAME  exclude NAME from the output (repeatable)
  --help                 print this message and exit
  --version              print version and exit
`

main :: proc() {
	help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{long = "help",    kind = .Bool_Last_Wins, target = &help,    value_if_set = true},
			{long = "version", kind = .Bool_Last_Wins, target = &version, value_if_set = true},
		},
	}

	// Pre-process args: extract -u / --unset NAME pairs before handing to cliflag.
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

	// Ignore any remaining positional args (kept for future NAME=VALUE support).
	_ = parsed.rest

	entries, ok := get_env()
	if !ok {
		winconsole.write_string(errw, "env: failed to read environment\r\n")
		os.exit(1)
	}
	defer {
		for e in entries { delete(e) }
		delete(entries)
	}

	for entry in entries {
		if should_exclude(entry, exclude[:]) { continue }
		winconsole.write_string(out, entry)
		winconsole.write_string(out, "\r\n")
	}
}
