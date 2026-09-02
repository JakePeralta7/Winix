package main

import "core:fmt"
import "core:os"
import "core:strings"
import "../../internal/cliflag"
import "../../internal/winconsole"

VERSION :: #config(VERSION, "dev")

USAGE :: `Usage: ps [OPTIONS]
Report a snapshot of the current processes.

  -e                 list all processes (default)
  -f                 do full-format listing
  -o FORMAT          user-defined format (comma-separated columns)
                     supported columns: pid, ppid, name, session, user
  -p PID[,PID...]    select processes by PID
  -u USER[,USER...]  select processes owned by USER
  -t SESSION[,...]   select processes in the given terminal session(s)
  --help             print this message and exit
  --version          print version and exit
`

main :: proc() {
	help, version: bool
	all: bool
	full: bool
	format_list: [dynamic]string
	pid_list:    [dynamic]string
	user_list:   [dynamic]string
	tty_list:    [dynamic]string

	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{long = "help",    kind = .Bool_Last_Wins, target = &help,    value_if_set = true},
			{long = "version", kind = .Bool_Last_Wins, target = &version, value_if_set = true},
			{short = 'e', long = "everyone", kind = .Bool_Last_Wins, target = &all, value_if_set = true},
			{short = 'f', long = "full",     kind = .Bool_Last_Wins, target = &full, value_if_set = true},
			{short = 'o', long = "format",   kind = .Value_Next,     values = &format_list},
			{short = 'p', long = "pid",      kind = .Value_Next,     values = &pid_list},
			{short = 'u', long = "user",     kind = .Value_Next,     values = &user_list},
			{short = 't', long = "tty",      kind = .Value_Next,     values = &tty_list},
		},
	}

	args := os.args[1:] if len(os.args) > 1 else []string{}
	_, perr, tok := cliflag.parse(args, spec)

	out  := winconsole.stdout()
	errw := winconsole.stderr()

	if perr != .None {
		winconsole.write_string(errw, "ps: unknown option: ")
		winconsole.write_string(errw, tok)
		winconsole.write_string(errw, "\r\nTry 'ps --help'.\r\n")
		os.exit(2)
	}
	if help    { winconsole.write_string(out, USAGE); os.exit(0) }
	if version { winconsole.write_line(out, "ps (winix) " + VERSION); os.exit(0) }

	pids     := parse_u32_list(pid_list[:])
	sessions := parse_u32_list(tty_list[:])
	users    := parse_string_list(user_list[:])
	format   := join_tokens(format_list[:])

	procs, ok := list_processes()
	if !ok {
		winconsole.write_string(errw, "ps: failed to enumerate processes\r\n")
		os.exit(1)
	}

	need_owner := full || len(users) > 0 || strings.contains(format, "user")
	if need_owner {
		for &p in procs {
			if p.owner != "" { continue }
			p.owner = resolve_owner(p.pid)
		}
	}

	filtered := make([dynamic]Proc_Entry, 0, 64)
	for p in procs {
		if !pid_filter(p, pids)          { continue }
		if !session_filter(p, sessions)  { continue }
		if !user_filter(p, users)        { continue }
		append(&filtered, p)
	}

	cols := resolve_columns(format, full)

	if len(filtered) > 0 {
		print_header(out, cols)
	}
	for p in filtered {
		print_row(out, p, cols)
	}
	free_proc_list(procs)
	os.exit(0)
}

// join_tokens joins a list of value-flag tokens into one comma-separated string.
join_tokens :: proc(tokens: []string, allocator := context.temp_allocator) -> string {
	if len(tokens) == 0 { return "" }
	b := strings.builder_make(allocator)
	for i in 0..<len(tokens) {
		if i > 0 { strings.write_string(&b, ",") }
		strings.write_string(&b, tokens[i])
	}
	return strings.to_string(b)
}

// pid_filter returns true when p matches the given selection of PIDs.
pid_filter :: proc(p: Proc_Entry, pids: []u32) -> bool {
	if len(pids) == 0 { return true }
	for pid in pids {
		if u32(pid) == p.pid { return true }
	}
	return false
}

// session_filter returns true when p belongs to a selected session.
session_filter :: proc(p: Proc_Entry, sessions: []u32) -> bool {
	if len(sessions) == 0 { return true }
	for s in sessions {
		if u32(s) == p.session_id { return true }
	}
	return false
}

// user_filter returns true when p's owner matches a selected user.
user_filter :: proc(p: Proc_Entry, users: []string) -> bool {
	if len(users) == 0 { return true }
	for u in users {
		if strings.equal_fold(p.owner, u) {
			return true
		}
	}
	return false
}

Column_Kind :: enum {
	PID,
	PPID,
	Name,
	Session,
	User,
}

// resolve_columns picks the columns for output based on -o FORMAT / -f.
resolve_columns :: proc(format_val: string, full: bool, allocator := context.temp_allocator) -> []Column_Kind {
	if full {
		cols := make([]Column_Kind, 5, allocator)
		cols[0] = Column_Kind.PID
		cols[1] = Column_Kind.PPID
		cols[2] = Column_Kind.Session
		cols[3] = Column_Kind.User
		cols[4] = Column_Kind.Name
		return cols
	}
	if format_val == "" {
		cols := make([]Column_Kind, 3, allocator)
		cols[0] = Column_Kind.PID
		cols[1] = Column_Kind.PPID
		cols[2] = Column_Kind.Name
		return cols
	}
	cols := make([dynamic]Column_Kind, 0, 8, allocator)
	for raw in strings.split(format_val, ",") {
		part := strings.trim_space(raw)
		switch part {
		case "pid":     append(&cols, Column_Kind.PID)
		case "ppid":    append(&cols, Column_Kind.PPID)
		case "name":    append(&cols, Column_Kind.Name)
		case "session": append(&cols, Column_Kind.Session)
		case "user":    append(&cols, Column_Kind.User)
		case "comm", "commander", "args", "cmd":
			append(&cols, Column_Kind.Name)
		}
	}
	if len(cols) == 0 {
		append(&cols, Column_Kind.PID)
		append(&cols, Column_Kind.PPID)
		append(&cols, Column_Kind.Name)
	}
	return cols[:]
}

// header_label returns the column header text for a column kind.
header_label :: proc(c: Column_Kind) -> string {
	switch c {
	case .PID:     return "PID"
	case .PPID:    return "PPID"
	case .Session: return "SESS"
	case .User:    return "USER"
	case .Name:    return "Name"
	}
	return ""
}

// field_text returns the raw text of a column for printing.
field_text :: proc(p: Proc_Entry, c: Column_Kind) -> string {
	switch c {
	case .PID:     return fmt.tprintf("%d", p.pid)
	case .PPID:    return fmt.tprintf("%d", p.ppid)
	case .Session: return fmt.tprintf("%d", p.session_id)
	case .User:    return p.owner
	case .Name:    return p.name
	}
	return ""
}

// print_header writes the column headers, left-justified over 12 chars.
print_header :: proc(out: winconsole.Writer, cols: []Column_Kind) {
	for i in 0..<len(cols) {
		if i > 0 { winconsole.write_string(out, " ") }
		winconsole.write_string(out, fmt.tprintf("%-12s", header_label(cols[i])))
	}
	winconsole.write_string(out, "\r\n")
}

// print_row writes one process entry using the given columns.
print_row :: proc(out: winconsole.Writer, p: Proc_Entry, cols: []Column_Kind) {
	for i in 0..<len(cols) {
		if i > 0 { winconsole.write_string(out, " ") }
		winconsole.write_string(out, fmt.tprintf("%-12s", field_text(p, cols[i])))
	}
	winconsole.write_string(out, "\r\n")
}

// parse_u32_list splits a comma-separated list of u32 numbers.
parse_u32_list :: proc(list: []string, allocator := context.temp_allocator) -> []u32 {
	if len(list) == 0 { return nil }
	result := make([dynamic]u32, 0, 4, allocator)
	for token in list {
		for raw in strings.split(token, ",") {
			part := strings.trim_space(raw)
			if part == "" { continue }
			v, ok := str_to_u32(part)
			if ok { append(&result, v) }
		}
	}
	return result[:]
}

// parse_string_list splits comma separated strings from the given tokens.
parse_string_list :: proc(list: []string, allocator := context.temp_allocator) -> []string {
	if len(list) == 0 { return nil }
	result := make([dynamic]string, 0, 4, allocator)
	for token in list {
		for raw in strings.split(token, ",") {
			part := strings.trim_space(raw)
			if part != "" { append(&result, part) }
		}
	}
	return result[:]
}

// str_to_u32 parses a base-10 unsigned 32-bit integer.
str_to_u32 :: proc(s: string) -> (u32, bool) {
	n: u32
	for ch in s {
		if ch < '0' || ch > '9' { return 0, false }
		n = n * 10 + u32(ch - '0')
	}
	return n, len(s) > 0
}