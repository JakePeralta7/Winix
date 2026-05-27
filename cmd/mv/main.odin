package main

import "core:os"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winio"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: mv [-f] [-n] [-v] [--help] [--version] source dest
       mv [-f] [-n] [-v] [--help] [--version] source ... directory
Rename source to dest, or move source(s) into directory.

  -f, --force        do not prompt before overwriting (default)
  -n, --no-clobber   do not overwrite an existing file
  -v, --verbose      explain what is being done
  --help             print this message and exit
  --version          print version and exit
`

main :: proc() {
	force, no_clobber, verbose, help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'f', long = "force",      kind = .Bool_Last_Wins, target = &force,     value_if_set = true},
			{short = 'n', long = "no-clobber", kind = .Bool_Last_Wins, target = &no_clobber, value_if_set = true},
			{short = 'v', long = "verbose",    kind = .Bool_Last_Wins, target = &verbose,   value_if_set = true},
			{long  = "help",                   kind = .Bool_Last_Wins, target = &help,      value_if_set = true},
			{long  = "version",                kind = .Bool_Last_Wins, target = &version,   value_if_set = true},
		},
	}

	args := os.args[1:] if len(os.args) > 1 else []string{}
	parsed, perr, tok := cliflag.parse(args, spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "mv: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'mv --help'.\r\n")
		os.exit(2)
	}
	if help {
		winconsole.write_string(out, USAGE)
		os.exit(0)
	}
	if version {
		winconsole.write_line(out, "mv (winix) " + VERSION)
		os.exit(0)
	}

	paths := parsed.rest
	if len(paths) < 2 {
		winconsole.write_string(errw, "mv: missing destination operand\r\nTry 'mv --help'.\r\n")
		os.exit(1)
	}

	// -n (no-clobber) is the meaningful flag; -f exists for compatibility.
	_ = force

	notify: Notify_Proc = nil
	if verbose {
		notify = proc(src, dst: string) {
			w := winconsole.stdout()
			winconsole.write_string(w, "renamed '")
			winconsole.write_string(w, src)
			winconsole.write_string(w, "' -> '")
			winconsole.write_string(w, dst)
			winconsole.write_string(w, "'\r\n")
		}
	}

	dst := paths[len(paths)-1]
	srcs := paths[:len(paths)-1]

	exit_code := 0

	// Multiple sources require dst to be an existing directory.
	if len(srcs) > 1 && !winio.is_directory(dst) {
		winconsole.write_string(errw, "mv: target '")
		winconsole.write_string(errw, dst)
		winconsole.write_string(errw, "': Not a directory\r\n")
		os.exit(1)
	}

	for src in srcs {
		err := move(src, dst, no_clobber, notify)
		if err != .None {
			report_error(errw, src, dst, err)
			exit_code = 1
		}
	}

	os.exit(exit_code)
}

report_error :: proc(errw: winconsole.Writer, src, dst: string, err: Error) {
	winconsole.write_string(errw, "mv: cannot move '")
	winconsole.write_string(errw, src)
	winconsole.write_string(errw, "' to '")
	winconsole.write_string(errw, dst)
	winconsole.write_string(errw, "': ")
	winconsole.write_string(errw, message_for(err))
	winconsole.write_string(errw, "\r\n")
}

message_for :: proc(err: Error) -> string {
	switch err {
	case .None:         return ""
	case .Src_Not_Found: return "No such file or directory"
	case .Access_Denied: return "Permission denied"
	case .Move_Failed:  return "operation failed"
	}
	return "unknown error"
}
