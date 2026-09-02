package main

import "core:fmt"
import "core:os"
import "core:strings"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: pkill [OPTION]... PATTERN
Kill processes by name pattern.

  -d, --dry-run       list processes that would be matched without killing (-e)
  -e, --echo          list what is being killed
  -f, --full          match against the full command line / image path
  -n, --newest        select only the most recently started matching process
  -o, --oldest        select only the earliest started matching process
  -P, --parent PPID   only match processes whose parent PID is in the list
  -s, --session N     only match processes in one of these session IDs
  -v, --inverse       select processes that do NOT match
  -x, --exact         require an exact (full name) match
      --help          print this message and exit
      --version       print version and exit

On Windows all process termination is unconditional (no signal support).
Exit status is 0 if at least one process matched, 1 if none were found.
`

// parse_u32_list splits a comma-separated list into u32 values.
parse_u32_list :: proc(s: string) -> []u32 {
	buf := make([dynamic]u32, 0, 4, context.temp_allocator)
	curr := s
	for len(curr) > 0 {
		comma := strings.index_byte(curr, ',')
		// Use core:strconv? We keep a local parse for simplicity.
		part: string
		if comma < 0 {
			part = curr
			curr = ""
		} else {
			part = curr[:comma]
			curr = curr[comma+1:]
		}
		if n, ok := parse_int(part); ok {
			append(&buf, u32(n))
		}
	}
	return buf[:]
}

// parse_int parses an unsigned decimal integer.
parse_int :: proc(s: string) -> (int, bool) {
	if len(s) == 0 {
		return 0, false
	}
	n := 0
	for c in s {
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n*10 + int(c-'0')
	}
	return n, true
}

main :: proc() {
	exact, full, inverse, newest, oldest, dry_run, echo, help, version: bool
	parent_vals, session_vals, uid_vals, tty_vals: [dynamic]string
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'd', long = "dry-run",  kind = .Bool_Last_Wins, target = &dry_run,  value_if_set = true},
			{short = 'e', long = "echo",     kind = .Bool_Last_Wins, target = &echo,     value_if_set = true},
			{short = 'f', long = "full",     kind = .Bool_Last_Wins, target = &full,     value_if_set = true},
			{short = 'n', long = "newest",   kind = .Bool_Last_Wins, target = &newest,   value_if_set = true},
			{short = 'o', long = "oldest",   kind = .Bool_Last_Wins, target = &oldest,   value_if_set = true},
			{short = 'P', long = "parent",   kind = .Value_Next, values = &parent_vals},
			{short = 's', long = "session",  kind = .Value_Next, values = &session_vals},
			{short = 'u', long = "uid",      kind = .Value_Next, values = &uid_vals},
			{short = 't', long = "terminal", kind = .Value_Next, values = &tty_vals},
			{short = 'v', long = "inverse",  kind = .Bool_Last_Wins, target = &inverse, value_if_set = true},
			{short = 'x', long = "exact",    kind = .Bool_Last_Wins, target = &exact,   value_if_set = true},
			{             long = "help",     kind = .Bool_Last_Wins, target = &help,    value_if_set = true},
			{             long = "version",  kind = .Bool_Last_Wins, target = &version, value_if_set = true},
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

	// -d implies -e: always show what would be killed in dry-run mode.
	if dry_run {
		echo = true
	}

	parent_pids := parse_u32_list(parent_vals[len(parent_vals)-1] if len(parent_vals) > 0 else "")
	sessions    := parse_u32_list(session_vals[len(session_vals)-1] if len(session_vals) > 0 else "")

	action := "would kill" if dry_run else "killed"
	any_matched := false

	for pattern in patterns {
		opts := Match_Opts{
			pattern      = pattern,
			exact        = exact,
			full         = full,
			inverse      = inverse,
			newest       = newest,
			oldest       = oldest,
			dry_run      = dry_run,
			parent_pids  = parent_pids,
			sessions     = sessions,
		}
		results, rerr := kill_by_name(opts)
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
			if echo {
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