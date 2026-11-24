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

@(test)
assignment_is_passed_to_command :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{"WINIX_TEST=hello", "cmd.exe", "/c", "echo %WINIX_TEST%"})
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "hello"), "expected assigned value in child output")
}

@(test)
ignore_environment_applies_to_command :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{"-i", "WINIX_TEST=hello", "cmd.exe", "/c", "echo [%WINIX_TEST%][%PATH%]"})
	defer delete(out)
	testing.expect_value(t, code, 0)
	s := string(out)
	testing.expect(t, strings.contains(s, "[hello]"), "expected assignment to survive -i")
	testing.expect(t, !strings.contains(s, "C:\\"), "expected no inherited PATH in child")
}

@(test)
unset_applies_to_command :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{"-u", "COMPUTERNAME", "cmd.exe", "/c", "echo [%COMPUTERNAME%]"})
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "[%COMPUTERNAME%]"), "expected COMPUTERNAME to be unset")
}

@(test)
command_flags_are_not_consumed_by_env :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{"cmd.exe", "/c", "echo -u --help"})
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "-u --help"), "expected command flags to reach the child")
}

@(test)
command_exit_code_is_propagated :: proc(t: ^testing.T) {
	_, _, code := run(t, []string{"cmd.exe", "/c", "exit 7"})
	testing.expect_value(t, code, 7)
}

@(test)
missing_command_exits_1 :: proc(t: ^testing.T) {
	_, errb, code := run(t, []string{"definitely_missing_winix_command"})
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, len(errb) > 0, "expected error message on stderr")
}
