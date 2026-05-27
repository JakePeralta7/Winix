package ps_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/ps.exe"

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
shows_header :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{})
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "PID"),  "expected PID column header")
	testing.expect(t, strings.contains(string(out), "Name"), "expected Name column header")
}

@(test)
output_is_non_empty :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{})
	defer delete(out)
	testing.expect_value(t, code, 0)
	// There should be at least the header line and one process line.
	lines := strings.split_lines(strings.trim_right(string(out), "\r\n"), context.temp_allocator)
	testing.expect(t, len(lines) >= 2, "expected at least one process listed")
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
