// Package cliflag provides a minimal command-line flag parser.
//
// Callers describe expected flags with a Spec, then call parse to walk os.args.
// Unrecognised flags cause parse to return immediately with .Unknown_Flag and
// the offending token; all valid flags set their target pointer in place.
// Positional arguments (non-flag tokens) are returned in Parsed.rest.
package cliflag

// Parse_Error is the error class returned by parse.
Parse_Error :: enum {
    None,
    Unknown_Flag,
    Bad_Combo,  // reserved; not yet emitted
}

// Flag_Kind selects how a flag's value is applied when it appears.
Flag_Kind :: enum {
    // Bool_Last_Wins writes value_if_set to the target every time the flag
    // appears, so the last occurrence wins (e.g. -L -P leaves -P in effect).
    Bool_Last_Wins,
}

// Flag_Def declares one recognised flag.
// Set short to 0 or long to "" to make a flag short-only or long-only.
Flag_Def :: struct {
    long:         string, // "" if short-only
    short:        rune,   // 0 if long-only
    kind:         Flag_Kind,
    target:       ^bool,
    value_if_set: bool,   // value written to target^ when the flag appears
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
// rest is allocated from context.temp_allocator.
parse :: proc(args: []string, spec: Spec) -> (Parsed, Parse_Error, string) {
    rest := make([dynamic]string, 0, len(args), context.temp_allocator)
    for arg in args {
        if len(arg) >= 3 && arg[0] == '-' && arg[1] == '-' {
            name := arg[2:]
            def, ok := find_long(spec, name)
            if !ok {
                return Parsed{rest = rest[:]}, .Unknown_Flag, arg
            }
            def.target^ = def.value_if_set
            continue
        }
        if len(arg) >= 2 && arg[0] == '-' && arg[1] != '-' {
            for r in arg[1:] {
                def, ok := find_short(spec, r)
                if !ok {
                    return Parsed{rest = rest[:]}, .Unknown_Flag, arg
                }
                def.target^ = def.value_if_set
            }
            continue
        }
        append(&rest, arg)
    }
    return Parsed{rest = rest[:]}, .None, ""
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
