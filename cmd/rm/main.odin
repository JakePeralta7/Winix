package main

import "core:os"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: rm [OPTION]... [FILE]...
Remove (unlink) the FILE(s).

  -d, --dir           remove empty directories
  -f, --force         ignore nonexistent files and arguments, never prompt
  -i, --interactive   prompt before every removal
  -I                  prompt once before removing more than three files,
                      or when removing recursively
  -r, -R, --recursive remove directories and their contents recursively
  -v, --verbose       explain what is being done
      --help          print this message and exit
      --version       print version and exit
By default, rm does not remove directories.
`

main :: proc() {
	recursive, force, verbose, interactive, dir, prompt_many, help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'd', long = "dir",         kind = .Bool_Last_Wins, target = &dir,          value_if_set = true},
			{short = 'f', long = "force",       kind = .Bool_Last_Wins, target = &force,        value_if_set = true},
			{short = 'i', long = "interactive", kind = .Bool_Last_Wins, target = &interactive,  value_if_set = true},
			{short = 'I',                      kind = .Bool_Last_Wins, target = &prompt_many,  value_if_set = true},
			{short = 'r', long = "recursive",  kind = .Bool_Last_Wins, target = &recursive,    value_if_set = true},
			{short = 'R',                      kind = .Bool_Last_Wins, target = &recursive,    value_if_set = true},
			{short = 'v', long = "verbose",    kind = .Bool_Last_Wins, target = &verbose,      value_if_set = true},
			{             long = "help",       kind = .Bool_Last_Wins, target = &help,         value_if_set = true},
			{             long = "version",    kind = .Bool_Last_Wins, target = &version,      value_if_set = true},
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

	// When no paths are given as arguments, try to read them from stdin (pipe).
	if len(paths) == 0 {
		if stdin_lines := winconsole.read_stdin_lines(); stdin_lines != nil {
			paths = stdin_lines
		}
	}

	if len(paths) == 0 {
		winconsole.write_string(errw, "rm: missing operand\r\nTry 'rm --help'.\r\n")
		os.exit(1)
	}

	// -f overrides -i; -I prompts once, not per-file.
	force_mode := force
	prompt_each := interactive && !force_mode

	// Build the notify callback for -v.
	notify: Notify_Proc = nil
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

	// Build the per-file prompt callback for -i.
	prompt: Prompt_Proc = nil
	if prompt_each {
		prompt = proc(path: string, is_dir: bool) -> bool {
			errc := winconsole.stderr()
			kind := "file"
			if is_dir { kind = "directory" }
			winconsole.write_string(errc, "rm: remove ")
			winconsole.write_string(errc, kind)
			winconsole.write_string(errc, " '")
			winconsole.write_string(errc, path)
			winconsole.write_string(errc, "'? ")
			return winconsole.prompt_yes_no(errc, "")
		}
	}

	opts := Options{
		prompt    = prompt,
		notify    = notify,
		allow_dir = dir,
	}

	// -I: prompt once before proceeding (when recursive or >3 files).
	if prompt_many && !force_mode {
		should_prompt := recursive || len(paths) > 3
		if should_prompt {
			question := "rm: remove all arguments recursively? "
			if !recursive {
				question = "rm: remove all arguments? "
			}
			if !winconsole.prompt_yes_no(errw, question) {
				os.exit(0)
			}
		}
	}

	exit_code := 0
	for path in paths {
		err: Error
		if recursive {
			err = remove_all(path, opts)
		} else {
			err = remove(path, opts)
		}

		if err == .None { continue }
		if err == .Not_Found && force_mode { continue }
		report_error(errw, path, err)
		exit_code = 1
	}
	os.exit(exit_code)
}

report_error :: proc(errw: winconsole.Writer, path: string, err: Error) {
	winconsole.write_string(errw, "rm: cannot remove '")
	winconsole.write_string(errw, path)
	winconsole.write_string(errw, "': ")
	winconsole.write_string(errw, message_for(err))
	winconsole.write_string(errw, "\r\n")
}

message_for :: proc(err: Error) -> string {
	switch err {
	case .None:          return ""
	case .Not_Found:     return "No such file or directory"
	case .Is_Directory:  return "Is a directory"
	case .Access_Denied: return "Permission denied"
	case .Remove_Failed: return "Operation not permitted"
	}
	return "unknown error"
}
