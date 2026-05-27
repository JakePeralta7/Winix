package main

import "core:os"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: du [-s] [-a] [-h] [--help] [--version] [path ...]
Estimate file space usage.

  -s, --summarize       display only a total for each argument
  -a, --all             print sizes for all files, not just directories
  -h, --human-readable  print sizes in human-readable form (e.g. 1.4M)
  --help                print this message and exit
  --version             print version and exit

Sizes are in 1 KiB blocks unless -h is given.
`

main :: proc() {
	summarize, all, human, help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 's', long = "summarize",      kind = .Bool_Last_Wins, target = &summarize, value_if_set = true},
			{short = 'a', long = "all",            kind = .Bool_Last_Wins, target = &all,       value_if_set = true},
			{short = 'h', long = "human-readable", kind = .Bool_Last_Wins, target = &human,     value_if_set = true},
			{long  = "help",                       kind = .Bool_Last_Wins, target = &help,      value_if_set = true},
			{long  = "version",                    kind = .Bool_Last_Wins, target = &version,   value_if_set = true},
		},
	}

	args := os.args[1:] if len(os.args) > 1 else []string{}
	parsed, perr, tok := cliflag.parse(args, spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "du: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'du --help'.\r\n")
		os.exit(2)
	}
	if help    { winconsole.write_string(out, USAGE); os.exit(0) }
	if version { winconsole.write_line(out, "du (winix) " + VERSION); os.exit(0) }

	paths := parsed.rest
	if len(paths) == 0 {
		paths = []string{"."}
	}

	opts := Du_Opts{summarize = summarize, all = all, human_readable = human}
	exit_code := 0

	for path in paths {
		if !path_exists(path) {
			winconsole.write_string(errw, "du: cannot access '")
			winconsole.write_string(errw, path)
			winconsole.write_string(errw, "': no such file or directory\r\n")
			exit_code = 1
			continue
		}
		total := du_path(path, opts, out)
		print_du_line(out, total, path, human)
	}

	os.exit(exit_code)
}
