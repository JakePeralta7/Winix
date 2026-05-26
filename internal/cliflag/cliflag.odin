package cliflag

Parse_Error :: enum {
    None,
    Unknown_Flag,
    Bad_Combo,  // reserved; not yet emitted
}

Flag_Kind :: enum {
    Bool_Last_Wins,
}

Flag_Def :: struct {
    long:         string, // "" if short-only
    short:        rune,   // 0 if long-only
    kind:         Flag_Kind,
    target:       ^bool,
    value_if_set: bool,   // value written to target^ when the flag appears
}

Spec :: struct {
    flags: []Flag_Def,
}

Parsed :: struct {
    rest: []string, // positional args (slice into args)
}

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
