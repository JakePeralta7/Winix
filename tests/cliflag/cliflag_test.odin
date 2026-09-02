package cliflag_test

import "core:testing"
import "../../internal/cliflag"

@(test)
parse_value_next_takes_following_arg :: proc(t: ^testing.T) {
	lines: [dynamic]string
	help, version: bool
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'n', long = "lines", kind = .Value_Next, values = &lines},
			{long  = "help",    kind = .Bool_Last_Wins, target = &help,    value_if_set = true},
			{long  = "version", kind = .Bool_Last_Wins, target = &version, value_if_set = true},
		},
	}
	parsed, err, tok := cliflag.parse({"-n", "5", "foo"}, spec)
	testing.expect_value(t, err, cliflag.Parse_Error.None)
	testing.expect_value(t, tok, "")
	testing.expect_value(t, len(lines), 1)
	testing.expect_value(t, lines[0], "5")
	testing.expect_value(t, len(parsed.rest), 1)
	testing.expect_value(t, parsed.rest[0], "foo")
	delete(lines)
}

@(test)
parse_value_next_long_with_equals :: proc(t: ^testing.T) {
	lines: [dynamic]string
	spec := cliflag.Spec{flags = []cliflag.Flag_Def{{long = "lines", kind = .Value_Next, values = &lines}}}
	_, err, _ := cliflag.parse({"--lines=7"}, spec)
	testing.expect_value(t, err, cliflag.Parse_Error.None)
	testing.expect_value(t, len(lines), 1)
	testing.expect_value(t, lines[0], "7")
	delete(lines)
}

@(test)
parse_value_next_long_space_form :: proc(t: ^testing.T) {
	lines: [dynamic]string
	spec := cliflag.Spec{flags = []cliflag.Flag_Def{{long = "lines", kind = .Value_Next, values = &lines}}}
	_, err, _ := cliflag.parse({"--lines", "7"}, spec)
	testing.expect_value(t, err, cliflag.Parse_Error.None)
	testing.expect_value(t, len(lines), 1)
	testing.expect_value(t, lines[0], "7")
	delete(lines)
}

@(test)
parse_value_next_missing_returns_error :: proc(t: ^testing.T) {
	lines: [dynamic]string
	spec := cliflag.Spec{flags = []cliflag.Flag_Def{{short = 'n', kind = .Value_Next, values = &lines}}}
	_, err, tok := cliflag.parse({"-n"}, spec)
	testing.expect_value(t, err, cliflag.Parse_Error.Missing_Value)
	testing.expect_value(t, tok, "-n")
	delete(lines)
}

@(test)
parse_value_attached_short :: proc(t: ^testing.T) {
	lines: [dynamic]string
	spec := cliflag.Spec{flags = []cliflag.Flag_Def{{short = 'n', kind = .Value_Attached, values = &lines}}}
	parsed, err, _ := cliflag.parse({"-n5", "x"}, spec)
	testing.expect_value(t, err, cliflag.Parse_Error.None)
	testing.expect_value(t, len(lines), 1)
	testing.expect_value(t, lines[0], "5")
	testing.expect_value(t, len(parsed.rest), 1)
	delete(lines)
}

@(test)
parse_value_attached_missing_returns_error :: proc(t: ^testing.T) {
	lines: [dynamic]string
	spec := cliflag.Spec{flags = []cliflag.Flag_Def{{short = 'n', kind = .Value_Attached, values = &lines}}}
	_, err, _ := cliflag.parse({"-n"}, spec)
	testing.expect_value(t, err, cliflag.Parse_Error.Missing_Value)
	delete(lines)
}

@(test)
parse_value_repeatable_collects_all :: proc(t: ^testing.T) {
	pat: [dynamic]string
	spec := cliflag.Spec{flags = []cliflag.Flag_Def{{short = 'e', long = "regexp", kind = .Value_Next, values = &pat}}}
	_, err, _ := cliflag.parse({"-e", "foo", "--regexp=bar", "-ebaz"}, spec)
	testing.expect_value(t, err, cliflag.Parse_Error.None)
	testing.expect_value(t, len(pat), 3)
	testing.expect_value(t, pat[0], "foo")
	testing.expect_value(t, pat[1], "bar")
	testing.expect_value(t, pat[2], "baz")
	delete(pat)
}

@(test)
parse_value_optional_bare_uses_default :: proc(t: ^testing.T) {
	color: [dynamic]string
	spec := cliflag.Spec{flags = []cliflag.Flag_Def{{long = "color", kind = .Value_Optional, values = &color, optional_default = "always"}}}
	parsed, err, _ := cliflag.parse({"--color"}, spec)
	testing.expect_value(t, err, cliflag.Parse_Error.None)
	testing.expect_value(t, len(parsed.rest), 0)
	testing.expect_value(t, len(color), 1)
	testing.expect_value(t, color[0], "always")
	delete(color)
}

@(test)
parse_value_optional_with_value :: proc(t: ^testing.T) {
	color: [dynamic]string
	spec := cliflag.Spec{flags = []cliflag.Flag_Def{{long = "color", kind = .Value_Optional, values = &color, optional_default = "always"}}}
	_, err, _ := cliflag.parse({"--color=auto"}, spec)
	testing.expect_value(t, err, cliflag.Parse_Error.None)
	testing.expect_value(t, len(color), 1)
	testing.expect_value(t, color[0], "auto")
	delete(color)
}

@(test)
parse_double_dash_ends_flags :: proc(t: ^testing.T) {
	help: bool
	spec := cliflag.Spec{flags = []cliflag.Flag_Def{{long = "help", kind = .Bool_Last_Wins, target = &help, value_if_set = true}}}
	parsed, err, _ := cliflag.parse({"--", "--help", "-n", "x"}, spec)
	testing.expect_value(t, err, cliflag.Parse_Error.None)
	testing.expect_value(t, help, false)
	testing.expect_value(t, len(parsed.rest), 3)
	testing.expect_value(t, parsed.rest[0], "--help")
}

@(test)
parse_bundle_with_value_flag_attached :: proc(t: ^testing.T) {
	v_flag: bool
	lines: [dynamic]string
	spec := cliflag.Spec{
		flags = []cliflag.Flag_Def{
			{short = 'v', kind = .Bool_Last_Wins, target = &v_flag, value_if_set = true},
			{short = 'n', kind = .Value_Next, values = &lines},
		},
	}
	_, err, _ := cliflag.parse({"-vn5"}, spec)
	testing.expect_value(t, err, cliflag.Parse_Error.None)
	testing.expect_value(t, v_flag, true)
	testing.expect_value(t, len(lines), 1)
	testing.expect_value(t, lines[0], "5")
	delete(lines)
}

@(test)
parse_obsolete_number_valid_lines :: proc(t: ^testing.T) {
	n, unit, ok := cliflag.parse_obsolete_number("-50")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, n, u64(50))
	testing.expect_value(t, unit, cliflag.Obsolete_Unit.Lines)
}

@(test)
parse_obsolete_number_bytes_c :: proc(t: ^testing.T) {
	n, unit, ok := cliflag.parse_obsolete_number("-50c")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, n, u64(50))
	testing.expect_value(t, unit, cliflag.Obsolete_Unit.Bytes)
}

@(test)
parse_obsolete_number_k_multiplier :: proc(t: ^testing.T) {
	n, unit, ok := cliflag.parse_obsolete_number("-2k")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, n, u64(2 * 1024))
	testing.expect_value(t, unit, cliflag.Obsolete_Unit.Bytes)
}

@(test)
parse_obsolete_number_explicit_l :: proc(t: ^testing.T) {
	n, unit, ok := cliflag.parse_obsolete_number("-3l")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, n, u64(3))
	testing.expect_value(t, unit, cliflag.Obsolete_Unit.Lines)
}

@(test)
parse_obsolete_number_rejects_nonnumber :: proc(t: ^testing.T) {
	_, _, ok := cliflag.parse_obsolete_number("-abc")
	testing.expect_value(t, ok, false)
}

@(test)
parse_obsolete_number_ignores_q :: proc(t: ^testing.T) {
	n, _, ok := cliflag.parse_obsolete_number("-10q")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, n, u64(10))
}

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
