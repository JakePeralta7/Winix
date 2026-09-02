package main

import "core:os"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winio"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: mv [OPTION]... [-T] SOURCE DEST
   or:  mv [OPTION]... SOURCE... DIRECTORY
   or:  mv [OPTION]... -t DIRECTORY SOURCE...
Rename SOURCE to DEST, or move SOURCE(s) to DIRECTORY.

  -f, --force                  do not prompt before overwriting (default)
  -i, --interactive            prompt before overwrite
  -n, --no-clobber             do not overwrite an existing file
  -u, --update                 move only when SOURCE is newer than DEST
                               or DEST is missing
  -v, --verbose                explain what is being done
  -t, --target-directory=DIR   move all SOURCE arguments into DIR
  -T, --no-target-directory    treat DEST as a normal file
      --help                   display this help and exit
      --version                output version information and exit
`

main :: proc() {
	force, interactive, no_clobber, update, verbose, no_tgt, help, version: bool
	target_dir: [dynamic]string
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'f', long = "force",               kind = .Bool_Last_Wins, target = &force,      value_if_set = true},
			{short = 'i', long = "interactive",         kind = .Bool_Last_Wins, target = &interactive, value_if_set = true},
			{short = 'n', long = "no-clobber",          kind = .Bool_Last_Wins, target = &no_clobber,  value_if_set = true},
			{short = 'u', long = "update",              kind = .Bool_Last_Wins, target = &update,     value_if_set = true},
			{short = 'v', long = "verbose",             kind = .Bool_Last_Wins, target = &verbose,    value_if_set = true},
			{short = 't', long = "target-directory",    kind = .Value_Next, values = &target_dir},
			{short = 'T', long = "no-target-directory", kind = .Bool_Last_Wins, target = &no_tgt,     value_if_set = true},
			{             long = "help",                kind = .Bool_Last_Wins, target = &help,       value_if_set = true},
			{             long = "version",             kind = .Bool_Last_Wins, target = &version,    value_if_set = true},
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

	// -f overrides -i (last wins handled by parser); if interactive was given
	// with -f, force disables prompting.
	prompt_enabled := interactive && !force

	paths := parsed.rest
	if len(target_dir) > 0 {
		// -t DIR: all positional args are sources.
		if len(paths) == 0 {
			winconsole.write_string(errw, "mv: missing file operand\r\nTry 'mv --help'.\r\n")
			os.exit(1)
		}
		tgt := target_dir[len(target_dir)-1]
		dst := tgt
		srcs := paths
		exit_code := run_moves(errw, srcs, dst, prompt_enabled, no_clobber, update, verbose, no_tgt)
		os.exit(exit_code)
	}

	if len(paths) < 2 {
		winconsole.write_string(errw, "mv: missing destination operand\r\nTry 'mv --help'.\r\n")
		os.exit(1)
	}

	dst := paths[len(paths)-1]
	srcs := paths[:len(paths)-1]
	exit_code := run_moves(errw, srcs, dst, prompt_enabled, no_clobber, update, verbose, no_tgt)
	os.exit(exit_code)
}

run_moves :: proc(errw: winconsole.Writer, srcs: []string, dst: string, prompt_enabled, no_clobber, update, verbose, no_tgt: bool) -> int {
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

	prompt: Prompt_Proc
	if prompt_enabled {
		prompt = proc(dst: string) -> bool {
			errc := winconsole.stderr()
			winconsole.write_string(errc, "mv: overwrite '")
			winconsole.write_string(errc, dst)
			winconsole.write_string(errc, "'? ")
			return winconsole.prompt_yes_no(errc, "")
		}
	}

	opts := Move_Opts{
		no_clobber    = no_clobber,
		update        = update,
		no_target_dir = no_tgt,
		prompt        = prompt,
		notify        = notify,
	}

	// Multiple sources require dst to be an existing directory, unless -T was
	// given (then dst is a plain file — an error for multiple sources).
	if !no_tgt {
		if len(srcs) > 1 && !winio.is_directory(dst) {
			winconsole.write_string(errw, "mv: target '")
			winconsole.write_string(errw, dst)
			winconsole.write_string(errw, "': Not a directory\r\n")
			return 1
		}
	} else {
		if len(srcs) > 1 {
			winconsole.write_string(errw, "mv: extra operand '")
			winconsole.write_string(errw, srcs[1])
			winconsole.write_string(errw, "'\r\nTry 'mv --help'.\r\n")
			return 1
		}
	}

	exit_code := 0
	for src in srcs {
		err := move(src, dst, opts)
		if err != .None {
			report_error(errw, src, dst, err)
			exit_code = 1
		}
	}
	return exit_code
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