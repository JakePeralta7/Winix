package env_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/env.exe"

@(private = "file")
run :: proc(t: ^testing.T, args: []string) -> (stdout: []byte, stderr: []byte, code: int) {
	full := make([]string, 1 + len(args), context.temp_allocator)
	full[0] = EXE
	for a, i in args { full[1+i] = a }
	state, out, errb, err := os.process_exec(
		os.Process_Desc{command = full},
		context.allocator,
	)
	if err != nil { testing.fail_now(t, "process_exec failed") }
	return out, errb, state.exit_code
}

@(test)
no_args_exits_0 :: proc(t: ^testing.T) {
	_, _, code := run(t, []string{})
	testing.expect_value(t, code, 0)
}

@(test)
prints_environment_variables :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{})
	defer delete(out)
	testing.expect_value(t, code, 0)
	// PATH is always set on Windows.
	testing.expect(t, strings.contains(string(out), "PATH="), "expected PATH= in output")
}

@(test)
output_has_name_equals_value_format :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{})
	defer delete(out)
	testing.expect_value(t, code, 0)
	lines := strings.split_lines(strings.trim_right(string(out), "\r\n"), context.temp_allocator)
	for line in lines {
		if len(line) == 0 { continue }
		testing.expect(t, strings.contains(line, "="), "each line should contain '='")
		break
	}
}

@(test)
unset_flag_excludes_variable :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{"-u", "COMPUTERNAME"})
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, !strings.contains(string(out), "COMPUTERNAME="), "COMPUTERNAME should be excluded")
}

@(test)
help_exits_0 :: proc(t: ^testing.T) {
	_, _, code := run(t, []string{"--help"})
	testing.expect_value(t, code, 0)
}

@(test)
version_exits_0 :: proc(t: ^testing.T) {
	_, _, code := run(t, []string{"--version"})
	testing.expect_value(t, code, 0)
}
