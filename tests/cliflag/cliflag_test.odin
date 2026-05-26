package cliflag_test

import "core:testing"
import "../../internal/cliflag"

@(test)
parse_no_args_returns_defaults :: proc(t: ^testing.T) {
    physical, help, version: bool
    spec := cliflag.Spec{
        flags = []cliflag.Flag_Def{
            {short = 'L', kind = .Bool_Last_Wins, target = &physical, value_if_set = false},
            {short = 'P', kind = .Bool_Last_Wins, target = &physical, value_if_set = true},
            {long  = "help",    kind = .Bool_Last_Wins, target = &help,    value_if_set = true},
            {long  = "version", kind = .Bool_Last_Wins, target = &version, value_if_set = true},
        },
    }
    parsed, err, tok := cliflag.parse({}, spec)
    testing.expect_value(t, err, cliflag.Parse_Error.None)
    testing.expect_value(t, tok, "")
    testing.expect_value(t, physical, false)
    testing.expect_value(t, help, false)
    testing.expect_value(t, version, false)
    testing.expect_value(t, len(parsed.rest), 0)
}

@(private="file")
pwd_spec :: proc(physical, help, version: ^bool) -> cliflag.Spec {
    flags := make([]cliflag.Flag_Def, 4, context.temp_allocator)
    flags[0] = {short = 'L', kind = .Bool_Last_Wins, target = physical, value_if_set = false}
    flags[1] = {short = 'P', kind = .Bool_Last_Wins, target = physical, value_if_set = true}
    flags[2] = {long  = "help",    kind = .Bool_Last_Wins, target = help,    value_if_set = true}
    flags[3] = {long  = "version", kind = .Bool_Last_Wins, target = version, value_if_set = true}
    return cliflag.Spec{flags = flags}
}

@(test)
parse_dash_P_sets_physical :: proc(t: ^testing.T) {
    physical, help, version: bool
    parsed, err, _ := cliflag.parse({"-P"}, pwd_spec(&physical, &help, &version))
    testing.expect_value(t, err, cliflag.Parse_Error.None)
    testing.expect_value(t, physical, true)
    testing.expect_value(t, len(parsed.rest), 0)
}

@(test)
parse_dash_L_sets_physical_false :: proc(t: ^testing.T) {
    physical := true
    help, version: bool
    _, err, _ := cliflag.parse({"-L"}, pwd_spec(&physical, &help, &version))
    testing.expect_value(t, err, cliflag.Parse_Error.None)
    testing.expect_value(t, physical, false)
}

@(test)
parse_L_then_P_last_wins :: proc(t: ^testing.T) {
    physical, help, version: bool
    _, err, _ := cliflag.parse({"-L", "-P"}, pwd_spec(&physical, &help, &version))
    testing.expect_value(t, err, cliflag.Parse_Error.None)
    testing.expect_value(t, physical, true)
}

@(test)
parse_P_then_L_last_wins :: proc(t: ^testing.T) {
    physical, help, version: bool
    _, err, _ := cliflag.parse({"-P", "-L"}, pwd_spec(&physical, &help, &version))
    testing.expect_value(t, err, cliflag.Parse_Error.None)
    testing.expect_value(t, physical, false)
}

@(test)
parse_unknown_short_returns_error :: proc(t: ^testing.T) {
    physical, help, version: bool
    _, err, tok := cliflag.parse({"-X"}, pwd_spec(&physical, &help, &version))
    testing.expect_value(t, err, cliflag.Parse_Error.Unknown_Flag)
    testing.expect_value(t, tok, "-X")
}

@(test)
parse_long_help :: proc(t: ^testing.T) {
    physical, help, version: bool
    _, err, _ := cliflag.parse({"--help"}, pwd_spec(&physical, &help, &version))
    testing.expect_value(t, err, cliflag.Parse_Error.None)
    testing.expect_value(t, help, true)
}

@(test)
parse_long_version :: proc(t: ^testing.T) {
    physical, help, version: bool
    _, err, _ := cliflag.parse({"--version"}, pwd_spec(&physical, &help, &version))
    testing.expect_value(t, err, cliflag.Parse_Error.None)
    testing.expect_value(t, version, true)
}

@(test)
parse_unknown_long_returns_error :: proc(t: ^testing.T) {
    physical, help, version: bool
    _, err, tok := cliflag.parse({"--nope"}, pwd_spec(&physical, &help, &version))
    testing.expect_value(t, err, cliflag.Parse_Error.Unknown_Flag)
    testing.expect_value(t, tok, "--nope")
}

@(test)
parse_keeps_positional_in_rest :: proc(t: ^testing.T) {
    physical, help, version: bool
    parsed, err, _ := cliflag.parse({"-L", "foo", "bar"}, pwd_spec(&physical, &help, &version))
    testing.expect_value(t, err, cliflag.Parse_Error.None)
    testing.expect_value(t, len(parsed.rest), 2)
    testing.expect_value(t, parsed.rest[0], "foo")
    testing.expect_value(t, parsed.rest[1], "bar")
}

@(test)
parse_bundled_LP_last_wins_physical_true :: proc(t: ^testing.T) {
    physical, help, version: bool
    _, err, _ := cliflag.parse({"-LP"}, pwd_spec(&physical, &help, &version))
    testing.expect_value(t, err, cliflag.Parse_Error.None)
    testing.expect_value(t, physical, true)
}

@(test)
parse_bundled_PL_last_wins_physical_false :: proc(t: ^testing.T) {
    physical, help, version: bool
    _, err, _ := cliflag.parse({"-PL"}, pwd_spec(&physical, &help, &version))
    testing.expect_value(t, err, cliflag.Parse_Error.None)
    testing.expect_value(t, physical, false)
}
