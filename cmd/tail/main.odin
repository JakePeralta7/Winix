package main

import "core:os"
import "core:strconv"
import win "core:sys/windows"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winio"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: tail [OPTION]... [FILE]...
Print the last 10 lines of each FILE to standard output.
With no FILE, or when FILE is -, read standard input.

  -c, --bytes=[+]NUM       output the last NUM bytes; also use an offset from
                           the start of the file if NUM is prefixed with '+'
  -n, --lines=[+]NUM       output the last NUM lines, instead of the last 10;
                           use a prefix of '+' for the first NUM lines
  -q, --quiet, --silent    never output headers giving file names
  -v, --verbose            always output headers giving file names
  -z, --zero-terminated    line delimiter is NUL, not newline
  -f, --follow[={name|descriptor}] output appended data as the file grows
  -F                      same as --follow=name --retry
  -s, --sleep-interval=N   with -f, sleep roughly N seconds between iterations
      --help               display this help and exit
      --version            output version information and exit

NUM may have a multiplier suffix: b 512, kB 1000, K 1024, MB 1000*1000,
M 1024*1024, GB, G, T, and so on.
`

DEFAULT_LINES :: 10

main :: proc() {
	raw_args := os.args[1:] if len(os.args) > 1 else []string{}
	out  := winconsole.stdout()
	errw := winconsole.stderr()

	help, version, quiet, verbose, zflag, follow, retry: bool
	sleep_arg: [dynamic]string
	lines, bytes: [dynamic]string
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{long = "help",    kind = .Bool_Last_Wins, target = &help,    value_if_set = true},
			{long = "version", kind = .Bool_Last_Wins, target = &version, value_if_set = true},
			{long = "quiet", short = 'q', kind = .Bool_Last_Wins, target = &quiet, value_if_set = true},
			{long = "silent", kind = .Bool_Last_Wins, target = &quiet, value_if_set = true},
			{long = "verbose", short = 'v', kind = .Bool_Last_Wins, target = &verbose, value_if_set = true},
			{long = "zero-terminated", short = 'z', kind = .Bool_Last_Wins, target = &zflag, value_if_set = true},
			{long = "follow", short = 'f', kind = .Bool_Last_Wins, target = &follow, value_if_set = true},
			{long = "retry", kind = .Bool_Last_Wins, target = &retry, value_if_set = true},
			{long = "sleep-interval", short = 's', kind = .Value_Next, values = &sleep_arg},
			{long = "lines", short = 'n', kind = .Value_Next, values = &lines},
			{long = "bytes", short = 'c', kind = .Value_Next, values = &bytes},
		},
	}

	// Obsolete "-NUM" form recognised only as the very first argument.
	has_obsolete := false
	parse_args := raw_args
	if len(raw_args) > 0 {
		_, _, ok := cliflag.parse_obsolete_number(raw_args[0])
		if ok {
			has_obsolete = true
			parse_args = raw_args[1:]
		}
	}
	_ = retry

	parsed, perr, tok := cliflag.parse(parse_args, spec)
	if perr != .None {
		winconsole.write_string(errw, "tail: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'tail --help'.\r\n")
		os.exit(2)
	}
	if help {
		winconsole.write_string(out, USAGE)
		os.exit(0)
	}
	if version {
		winconsole.write_string(out, "tail (winix) " + VERSION + "\r\n")
		os.exit(0)
	}

	opts := Tail_Options{lines = -1, bytes = -1, delim = '\n'}
	if has_obsolete && len(raw_args) > 0 {
		count, unit, _ := cliflag.parse_obsolete_number(raw_args[0])
		switch unit {
		case .Lines:
			opts.lines = int(count)
		case .Bytes:
			opts.bytes = i64(count)
		}
	}
	if len(bytes) > 0 {
		v, ok := strconv.parse_i64(bytes[len(bytes)-1], 10)
		if !ok {
			fail_invalid(errw, "byte count", bytes[len(bytes)-1])
		}
		opts.bytes = v
	}
	if len(lines) > 0 {
		v, ok := strconv.parse_int(lines[len(lines)-1], 10)
		if !ok {
			fail_invalid(errw, "line count", lines[len(lines)-1])
		}
		opts.lines = v
	}
	if zflag {
		opts.delim = 0
	}
	if follow {
		opts.follow = true
	}
	_ = sleep_arg

	print_headers := (len(parsed.rest) > 1) && !quiet
	if verbose {
		print_headers = true
	}

	if len(parsed.rest) == 0 {
		h := win.GetStdHandle(win.STD_INPUT_HANDLE)
		if win.GetFileType(h) != win.FILE_TYPE_CHAR {
			if err := write_tail_from_stdin(opts); err != .None {
				winconsole.write_string(errw, "tail: error reading stdin\r\n")
				os.exit(1)
			}
			os.exit(0)
		}
		winconsole.write_string(errw, "tail: missing operand\r\nTry 'tail --help'.\r\n")
		os.exit(1)
	}

	exit_code := 0
	for path, idx in parsed.rest {
		if print_headers {
			if idx > 0 {
				winconsole.write_string(out, "\r\n")
			}
			winconsole.write_string(out, "==> ")
			winconsole.write_string(out, path)
			winconsole.write_string(out, " <==\r\n")
		}
		err := write_tail(path, opts)
		if err == .None { continue }
		report_error(errw, path, err)
		exit_code = 1
	}
	os.exit(exit_code)
}

fail_invalid :: proc(errw: winconsole.Writer, what, val: string) -> ! {
	winconsole.write_string(errw, "tail: invalid ")
	winconsole.write_string(errw, what)
	winconsole.write_string(errw, ": '")
	winconsole.write_string(errw, val)
	winconsole.write_string(errw, "'\r\nTry 'tail --help'.\r\n")
	os.exit(2)
}

report_error :: proc(errw: winconsole.Writer, path: string, err: winio.Error) {
	winconsole.write_string(errw, "tail: ")
	winconsole.write_string(errw, path)
	winconsole.write_string(errw, ": ")
	winconsole.write_string(errw, message_for(err))
	winconsole.write_string(errw, "\r\n")
}

message_for :: proc(err: winio.Error) -> string {
	switch err {
	case .None:          return ""
	case .Not_Found:     return "No such file or directory"
	case .Is_Directory:  return "Is a directory"
	case .Access_Denied: return "Permission denied"
	case .Open_Failed:   return "cannot open file"
	case .Read_Failed:   return "cannot read file"
	case .Write_Failed:  return "cannot write output"
	}
	return "unknown error"
}