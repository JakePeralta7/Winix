package main

import "core:os"
import "core:strings"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: env [OPTION]... [NAME=VALUE]... [COMMAND [ARG]...]
Run a program in a modified environment or print the current environment.

  -i, --ignore-environment  start with an empty environment
  -u, --unset=NAME          remove variable from the environment
  -0, --null                end printed output with NUL instead of newline
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
	filtered := make([dynamic]string, 0, len(raw_args), context.temp_allocator)

	// Stop flag parsing at the first real command token so its own flags are not
	// consumed by env. Assignments before it are still parsed as positionals.
	i := 0
	for i < len(raw_args) {
		arg := raw_args[i]
		if arg == "--" {
			append(&filtered, arg)
			for j := i + 1; j < len(raw_args); j += 1 { append(&filtered, raw_args[j]) }
			break
		}
		if arg == "-u" || arg == "--unset" {
			append(&filtered, arg)
			if i + 1 < len(raw_args) {
				append(&filtered, raw_args[i + 1])
				i += 2
			} else {
				i += 1
			}
			continue
		}
		if len(arg) >= 2 && arg[0] == '-' {
			append(&filtered, arg)
			i += 1
			continue
		}
		if strings.index_byte(arg, '=') > 0 {
			append(&filtered, arg)
			i += 1
			continue
		}

		append(&filtered, "--")
		for j := i; j < len(raw_args); j += 1 { append(&filtered, raw_args[j]) }
		break
	}

	parsed, perr, tok := cliflag.parse(filtered[:], spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		if perr == .Missing_Value {
			winconsole.write_string(errw, "env: option requires an argument: ")
		} else {
			winconsole.write_string(errw, "env: unknown option: ")
		}
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'env --help'.\r\n")
		os.exit(2)
	}
	if help    { winconsole.write_string(out, USAGE); os.exit(0) }
	if version { winconsole.write_line(out, "env (winix) " + VERSION); os.exit(0) }

	assignments := make([dynamic]string, 0, len(parsed.rest), context.temp_allocator)
	cmd_index := len(parsed.rest)
	for i := 0; i < len(parsed.rest); i += 1 {
		arg := parsed.rest[i]
		if strings.index_byte(arg, '=') <= 0 {
			cmd_index = i
			break
		}
		append(&assignments, arg)
	}

	entries, ok := get_env()
	if !ok {
		winconsole.write_string(errw, "env: failed to read environment\r\n")
		os.exit(1)
	}

	env_entries := build_entries(entries, unset_vals[:], assignments[:], ignore_env)

	if cmd_index >= len(parsed.rest) {
		delim := "\r\n"
		if null_term { delim = "\x00" }
		for entry in env_entries {
			winconsole.write_string(out, entry)
			winconsole.write_string(out, delim)
		}
		os.exit(0)
	}

	code, err := run_command(parsed.rest[cmd_index:], env_entries)
	if err != nil {
		winconsole.write_string(errw, "env: ")
		winconsole.write_string(errw, parsed.rest[cmd_index])
		winconsole.write_string(errw, ": ")
		winconsole.write_string(errw, os.error_string(err))
		winconsole.write_string(errw, "\r\n")
		os.exit(1)
	}
	os.exit(code)
}
