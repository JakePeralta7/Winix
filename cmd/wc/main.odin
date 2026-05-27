package main

import "core:fmt"
import "core:os"
import win "core:sys/windows"
import "../../internal/cliflag"
import "../../internal/winconsole"
import "../../internal/winio"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: wc [-l] [-w] [-c] [--help] [--version] [file ...]
Print newline, word, and byte counts for each file.

  -l, --lines   print the newline count
  -w, --words   print the word count
  -c, --bytes   print the byte count
  --help        print this message and exit
  --version     print version and exit

With no flags all three counts are printed. With no files reads from stdin.
`

print_counts :: proc(out: winconsole.Writer, c: Counts, label: string, lines, words, bytes: bool) {
	if lines { winconsole.write_string(out, fmt.tprintf(" %7d", c.lines)) }
	if words { winconsole.write_string(out, fmt.tprintf(" %7d", c.words)) }
	if bytes { winconsole.write_string(out, fmt.tprintf(" %7d", c.bytes)) }
	if label != "" {
		winconsole.write_string(out, " ")
		winconsole.write_string(out, label)
	}
	winconsole.write_string(out, "\r\n")
}

wc_error :: proc(err: winio.Error) -> string {
	switch err {
	case .Not_Found:     return "no such file or directory"
	case .Is_Directory:  return "is a directory"
	case .Access_Denied: return "permission denied"
	case .Read_Failed:   return "read error"
	case .Write_Failed:  return "write error"
	case .Open_Failed:   return "open failed"
	case .None:          return ""
	}
	return "error"
}

main :: proc() {
	show_lines, show_words, show_bytes, help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'l', long = "lines",   kind = .Bool_Last_Wins, target = &show_lines, value_if_set = true},
			{short = 'w', long = "words",   kind = .Bool_Last_Wins, target = &show_words, value_if_set = true},
			{short = 'c', long = "bytes",   kind = .Bool_Last_Wins, target = &show_bytes, value_if_set = true},
			{long  = "help",                kind = .Bool_Last_Wins, target = &help,       value_if_set = true},
			{long  = "version",             kind = .Bool_Last_Wins, target = &version,    value_if_set = true},
		},
	}

	args := os.args[1:] if len(os.args) > 1 else []string{}
	parsed, perr, tok := cliflag.parse(args, spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "wc: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'wc --help'.\r\n")
		os.exit(2)
	}
	if help    { winconsole.write_string(out, USAGE); os.exit(0) }
	if version { winconsole.write_line(out, "wc (winix) " + VERSION); os.exit(0) }

	// If no output flags were set, enable all three.
	if !show_lines && !show_words && !show_bytes {
		show_lines = true
		show_words = true
		show_bytes = true
	}

	files := parsed.rest
	exit_code := 0
	total: Counts

	if len(files) == 0 {
		h := win.GetStdHandle(win.STD_INPUT_HANDLE)
		if win.GetFileType(h) != win.FILE_TYPE_CHAR {
			c := count_stdin()
			print_counts(out, c, "", show_lines, show_words, show_bytes)
			os.exit(0)
		}
		winconsole.write_string(errw, "wc: missing operand\r\nTry 'wc --help'.\r\n")
		os.exit(1)
	}

	for path in files {
		c, err := count_file(path)
		if err != .None {
			winconsole.write_string(errw, "wc: ")
			winconsole.write_string(errw, path)
			winconsole.write_string(errw, ": ")
			winconsole.write_string(errw, wc_error(err))
			winconsole.write_string(errw, "\r\n")
			exit_code = 1
			continue
		}
		total.lines += c.lines
		total.words += c.words
		total.bytes += c.bytes
		print_counts(out, c, path, show_lines, show_words, show_bytes)
	}

	if len(files) > 1 {
		print_counts(out, total, "total", show_lines, show_words, show_bytes)
	}

	os.exit(exit_code)
}
