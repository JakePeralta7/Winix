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
    // Minimal: no flags parsed yet. Return all args as rest.
    return Parsed{rest = args}, .None, ""
}
