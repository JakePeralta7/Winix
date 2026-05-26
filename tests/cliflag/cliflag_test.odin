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
