// Package cliflag provides a minimal command-line flag parser.
//
// Callers describe expected flags with a Spec, then call parse to walk os.args.
// Unrecognised flags cause parse to return immediately with .Unknown_Flag and
// the offending token; all valid flags set their target pointer in place.
// Positional arguments (non-flag tokens) are returned in Parsed.rest.
//
// Two flag families are supported:
//   - Boolean flags (kind .Bool_Last_Wins) write true/false into a ^bool
//     target each time they appear, so the last occurrence wins.
//   - Value flags (kinds .Value_Next, .Value_Attached, .Value_Optional) collect
//     the raw string value(s) into a per-flag ^[dynamic]string. The caller is
//     responsible for converting the strings (to int, etc.) - cliflag stays
//     generic and only captures the argument text. Repeated appearances append.
//
// The token "--" terminates flag parsing: everything after it is treated as
// positional and returned in Parsed.rest.
package cliflag

import "core:strings"

// Parse_Error is the error class returned by parse.
Parse_Error :: enum {
	None,
	Unknown_Flag,
	Missing_Value, // a value flag appeared but no value was available
}

// Flag_Kind selects how a flag's value is applied when it appears.
Flag_Kind :: enum {
	// Bool_Last_Wins writes value_if_set to the target every time the flag
	// appears, so the last occurrence wins (e.g. -L -P leaves -P in effect).
	Bool_Last_Wins,
	// Value_Next takes its value from the immediately following argument
	// (e.g. "-n 5", "--lines 5").
	Value_Next,
	// Value_Attached takes its value appended to the flag token itself
	// (e.g. "-n5", "--lines=5"). A short flag consumes the rest of its token;
	// a long flag uses the "=" form.
	Value_Attached,
	// Value_Optional accepts an attached value but does not require one
	// (e.g. "--color", "--color=auto", "--interactive[=WHEN]"). When the flag
	// appears without a value, optional_default is appended to values.
	Value_Optional,
}

// Flag_Def declares one recognised flag.
// Set short to 0 or long to "" to make a flag short-only or long-only.
Flag_Def :: struct {
	long:   string, // "" if short-only
	short:  rune,   // 0 if long-only
	kind:   Flag_Kind,
	// Boolean flags: target ^bool written with value_if_set on each occurrence.
	target:        ^bool,
	value_if_set:  bool,
	// Value flags: values ^[dynamic]string appended with each occurrence.
	values:          ^[dynamic]string,
	optional_default: string, // value appended when .Value_Optional appears bare
}

// Spec is the complete description of a command's flags.
Spec :: struct {
	flags: []Flag_Def,
}

// Parsed holds the output of a successful (or partial) parse.
Parsed :: struct {
	rest: []string, // positional args that were not consumed as flags
}

// parse walks args left-to-right and applies matching Flag_Defs from spec.
//
// On success it returns (Parsed, .None, "").
// On the first unrecognised flag it returns the partial Parsed, .Unknown_Flag,
// and the offending token (e.g. "--foo" or "-z").
// On a value flag missing its value it returns .Missing_Value with the token.
// A token of exactly "--" stops flag parsing; all subsequent tokens are
// positional. rest is allocated from context.temp_allocator.
parse :: proc(args: []string, spec: Spec) -> (Parsed, Parse_Error, string) {
	rest := make([dynamic]string, 0, len(args), context.temp_allocator)

	i := 0
	for i < len(args) {
		arg := args[i]

		if arg == "--" {
			for j := i + 1; j < len(args); j += 1 {
				append(&rest, args[j])
			}
			return Parsed{rest = rest[:]}, .None, ""
		}

		if len(arg) >= 3 && arg[0] == '-' && arg[1] == '-' {
			token, attached, has_eq := split_long(arg)
			def, ok := find_long(spec, token)
			if !ok {
				return Parsed{rest = rest[:]}, .Unknown_Flag, arg
			}
			n, err := apply_long(def, arg, attached, has_eq, args, i)
			if err != .None {
				return Parsed{rest = rest[:]}, err, arg
			}
			i += n
			continue
		}

		if len(arg) >= 2 && arg[0] == '-' && arg[1] != '-' {
			n, err := parse_short(arg, spec, args, i)
			if err != .None {
				return Parsed{rest = rest[:]}, err, arg
			}
			i += n
			continue
		}

		append(&rest, arg)
		i += 1
	}

	return Parsed{rest = rest[:]}, .None, ""
}

// split_long splits a long-flag token into name and (optional) attached value.
// Returns has_eq=false when there is no '=' in the token.
@(private)
split_long :: proc(token: string) -> (name: string, attached: string, has_eq: bool) {
	name = token[2:]
	eq := strings.index_byte(name, '=')
	if eq < 0 {
		return name, "", false
	}
	return name[:eq], name[eq + 1:], true
}

// parse_short handles a single "-..." token. It returns the number of args
// consumed (1 or 2 when a .Value_Next flag consumes the next argument) and an
// error. Boolean flags may be bundled ("-abc"); a value flag is taken as
// short-with-attached-value ("-n5") or, when the token is exactly the flag
// (-n), as .Value_Next consuming the following arg.
@(private)
parse_short :: proc(arg: string, spec: Spec, args: []string, i: int) -> (consumed: int, err: Parse_Error) {
	first, ok := find_short(spec, rune(arg[1]))
	if !ok {
		return 0, .Unknown_Flag
	}

	// Boolean bundle: each letter is a separate boolean flag.
	if first.kind == .Bool_Last_Wins {
		for r in arg[1:] {
			d, ok2 := find_short(spec, r)
			if !ok2 {
				return 0, .Unknown_Flag
			}
			if d.kind != .Bool_Last_Wins {
				// A value flag in the middle of a bundle: not supported; treat
				// the remaining letters as its attached value.
				offset := strings.index_byte(arg, cast(u8)r)
				if offset < 0 {
					return 0, .Unknown_Flag
				}
				attached := arg[offset + 1:]
				n, err2 := apply_short_value(d, attached, args, i)
				return n, err2
			}
			d.target^ = d.value_if_set
		}
		return 1, .None
	}

	// Value flag: value is the rest of the token ("-n5") or the next arg.
	attached := arg[2:] // "" for a bare "-n"
	return apply_short_value(first, attached, args, i)
}

// apply_long applies a long-flag occurrence, returning args consumed and error.
@(private)
apply_long :: proc(def: Flag_Def, orig: string, attached: string, has_eq: bool, args: []string, i: int) -> (int, Parse_Error) {
	switch def.kind {
	case .Bool_Last_Wins:
		if has_eq {
			return 0, .Unknown_Flag
		}
		def.target^ = def.value_if_set
		return 1, .None
	case .Value_Next, .Value_Attached:
		if has_eq {
			append(def.values, attached)
			return 1, .None
		}
		if def.kind == .Value_Attached {
			return 0, .Missing_Value
		}
		if i + 1 >= len(args) {
			return 0, .Missing_Value
		}
		append(def.values, args[i + 1])
		return 2, .None
	case .Value_Optional:
		if has_eq {
			append(def.values, attached)
		} else {
			append(def.values, def.optional_default)
		}
		return 1, .None
	}
	return 0, .None
}

// apply_short_value applies a short value-flag occurrence. attached is the
// value taken from the token's tail ("" when none). Returns args consumed.
@(private)
apply_short_value :: proc(def: Flag_Def, attached: string, args: []string, i: int) -> (int, Parse_Error) {
	switch def.kind {
	case .Bool_Last_Wins:
		return 1, .None
	case .Value_Attached:
		if attached == "" {
			return 0, .Missing_Value
		}
		append(def.values, attached)
		return 1, .None
	case .Value_Next:
		if attached != "" {
			append(def.values, attached)
			return 1, .None
		}
		if i + 1 >= len(args) {
			return 0, .Missing_Value
		}
		append(def.values, args[i + 1])
		return 2, .None
	case .Value_Optional:
		if attached != "" {
			append(def.values, attached)
		} else {
			append(def.values, def.optional_default)
		}
		return 1, .None
	}
	return 1, .None
}

@(private)
find_short :: proc(spec: Spec, r: rune) -> (Flag_Def, bool) {
	for def in spec.flags {
		if def.short == r {
			return def, true
		}
	}
	return {}, false
}

@(private)
find_long :: proc(spec: Spec, name: string) -> (Flag_Def, bool) {
	for def in spec.flags {
		if def.long == name {
			return def, true
		}
	}
	return {}, false
}

// Obsolete_Unit describes how an obsolete "-NUM" head/tail option counts.
Obsolete_Unit :: enum {
	Lines,
	Bytes,
}

// parse_obsolete_number interprets the GNU "obsolete option syntax" shared by
// head and tail: -[num][bkm][cqv], where a trailing 'l' counts in lines
// (the default), 'c' counts in bytes, 'b'/'k'/'m' are byte-size multipliers,
// and 'q'/'v' are accepted-but-ignored. GNU recognises this form only when it
// is the FIRST argument.
//
// Example: "-50"   -> 50 lines
//          "-50c"  -> 50 bytes
//          "-2m"   -> 2*1024*1024 bytes
//          "-3l"   -> 3 lines
parse_obsolete_number :: proc(arg: string) -> (count: u64, unit: Obsolete_Unit, ok: bool) {
	if len(arg) < 2 || arg[0] != '-' {
		return 0, .Lines, false
	}
	s := arg[1:]
	count = 0
	digit := false
	for len(s) > 0 {
		c := s[0]
		if '0' <= c && c <= '9' {
			digit = true
			count = count * 10 + u64(c - '0')
			s = s[1:]
			continue
		}
		break
	}
	if !digit {
		return 0, .Lines, false
	}
	if len(s) >= 1 {
		switch s[0] {
		case 'l':
			unit = .Lines
			s = s[1:]
		case 'c':
			unit = .Bytes
			s = s[1:]
		case 'b':
			unit = .Bytes
			count *= 512
			s = s[1:]
		case 'k':
			unit = .Bytes
			count *= 1024
			s = s[1:]
		case 'm':
			unit = .Bytes
			count *= 1024 * 1024
			s = s[1:]
		case 'q', 'v':
			// Accepted but ignored.
			s = s[1:]
		case:
			return 0, .Lines, false
		}
	}
	return count, unit, len(s) == 0
}