package main

import "core:os"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winrm"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: rm [-r] [-f] [-v] [--help] [--version] file ...
Remove files or directories.

  -r, -R, --recursive  remove directories and their contents recursively
  -f, --force          ignore nonexistent files and arguments, never prompt
  -v, --verbose        explain what is being done
  --help               print this message and exit
  --version            print version and exit
`

main :: proc() {
	recursive, force, verbose, help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'r', long = "recursive", kind = .Bool_Last_Wins, target = &recursive, value_if_set = true},
			{short = 'R',                     kind = .Bool_Last_Wins, target = &recursive, value_if_set = true},
			{short = 'f', long = "force",     kind = .Bool_Last_Wins, target = &force,     value_if_set = true},
			{short = 'v', long = "verbose",   kind = .Bool_Last_Wins, target = &verbose,   value_if_set = true},
			{long  = "help",                  kind = .Bool_Last_Wins, target = &help,      value_if_set = true},
			{long  = "version",               kind = .Bool_Last_Wins, target = &version,   value_if_set = true},
		},
	}

	args := os.args[1:] if len(os.args) > 1 else []string{}
	parsed, perr, tok := cliflag.parse(args, spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "rm: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'rm --help'.\r\n")
		os.exit(2)
	}
	if help {
		winconsole.write_string(out, USAGE)
		os.exit(0)
	}
	if version {
		winconsole.write_line(out, "rm (winix) " + VERSION)
		os.exit(0)
	}

	paths := parsed.rest
	if len(paths) == 0 {
		winconsole.write_string(errw, "rm: missing operand\r\nTry 'rm --help'.\r\n")
		os.exit(1)
	}

	// notify is called by winrm after each successful deletion when -v is set.
	notify: winrm.Notify_Proc = nil
	if verbose {
		notify = proc(path: string, is_dir: bool) {
			w := winconsole.stdout()
			if is_dir {
				winconsole.write_string(w, "removed directory '")
			} else {
				winconsole.write_string(w, "removed '")
			}
			winconsole.write_string(w, path)
			winconsole.write_string(w, "'\r\n")
		}
	}

	exit_code := 0
	for path in paths {
		err: winrm.Error
		if recursive {
			err = winrm.remove_all(path, notify)
		} else {
			err = winrm.remove(path, notify)
		}

		if err == .None { continue }
		if err == .Not_Found && force { continue }
		report_error(errw, path, err)
		exit_code = 1
	}
	os.exit(exit_code)
}

report_error :: proc(errw: winconsole.Writer, path: string, err: winrm.Error) {
	winconsole.write_string(errw, "rm: cannot remove '")
	winconsole.write_string(errw, path)
	winconsole.write_string(errw, "': ")
	winconsole.write_string(errw, message_for(err))
	winconsole.write_string(errw, "\r\n")
}

message_for :: proc(err: winrm.Error) -> string {
	switch err {
	case .None:          return ""
	case .Not_Found:     return "No such file or directory"
	case .Is_Directory:  return "Is a directory"
	case .Access_Denied: return "Permission denied"
	case .Remove_Failed: return "Operation not permitted"
	}
	return "unknown error"
}
