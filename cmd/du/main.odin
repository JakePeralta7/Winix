package main

import "core:os"
import "core:strconv"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: du [OPTION]... [FILE]...
Estimate file space usage.

  -a, --all                    write counts for all files, not just directories
  -c, --total                  produce a grand total
  -d, --max-depth=N            print the total for a directory (or file)
                               only if it is N or fewer levels below the
                               command line argument
  -h, --human-readable         print sizes in human-readable form (e.g. 1.4M)
  -k                           like --block-size=1K (default)
  -m                           like --block-size=1M
  -s, --summarize              display only a total for each argument
      --help                   display this help and exit
      --version                output version information and exit

Sizes are in 1 KiB blocks unless -h is given.
`

main :: proc() {
	summarize, all, human, total, k, mb, help, version: bool
	depth_vals: [dynamic]string
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'a', long = "all",            kind = .Bool_Last_Wins, target = &all,       value_if_set = true},
			{short = 'c', long = "total",          kind = .Bool_Last_Wins, target = &total,     value_if_set = true},
			{short = 'd', long = "max-depth",      kind = .Value_Next, values = &depth_vals},
			{short = 'h', long = "human-readable", kind = .Bool_Last_Wins, target = &human,     value_if_set = true},
			{short = 'k',                         kind = .Bool_Last_Wins, target = &k,         value_if_set = true},
			{short = 'm',                         kind = .Bool_Last_Wins, target = &mb,        value_if_set = true},
			{short = 's', long = "summarize",     kind = .Bool_Last_Wins, target = &summarize, value_if_set = true},
			{             long = "help",          kind = .Bool_Last_Wins, target = &help,      value_if_set = true},
			{             long = "version",       kind = .Bool_Last_Wins, target = &version,   value_if_set = true},
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

	// Block size: -h (human) sets it; -m → 1M; otherwise 1K default.
	block_size: u64 = 1024
	if mb {
		block_size = 1024 * 1024
	}

	// Max depth: -d N, or -s implies -d 0.
	max_depth := -1 // unlimited
	if summarize {
		max_depth = 0
	}
	if len(depth_vals) > 0 {
		dv := depth_vals[len(depth_vals)-1]
		if n, ok := strconv.parse_int(dv, 10); ok {
			max_depth = n
		}
	}

	opts := Du_Opts{
		summarize      = summarize,
		all            = all,
		human_readable = human,
		block_size     = block_size,
		max_depth      = max_depth,
	}

	exit_code := 0
	grand_total: u64

	for path in paths {
		if !path_exists(path) {
			winconsole.write_string(errw, "du: cannot access '")
			winconsole.write_string(errw, path)
			winconsole.write_string(errw, "': no such file or directory\r\n")
			exit_code = 1
			continue
		}
		total_blocks := du_path(path, opts, out)
		print_du_line(out, total_blocks, path, opts)
		grand_total += total_blocks
	}

	if total && len(paths) > 1 {
		print_du_line(out, grand_total, "total", opts)
	}

	os.exit(exit_code)
}