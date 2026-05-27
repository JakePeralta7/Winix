package sleep_integration_test

import "core:os"
import "core:testing"

@(private = "file")
EXE :: "bin/sleep.exe"

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
zero_seconds_exits_0 :: proc(t: ^testing.T) {
	_, _, code := run(t, []string{"0"})
	testing.expect_value(t, code, 0)
}

@(test)
decimal_duration_exits_0 :: proc(t: ^testing.T) {
	_, _, code := run(t, []string{"0.001"})
	testing.expect_value(t, code, 0)
}

@(test)
multiple_durations_exits_0 :: proc(t: ^testing.T) {
	_, _, code := run(t, []string{"0", "0"})
	testing.expect_value(t, code, 0)
}

@(test)
missing_operand_exits_1 :: proc(t: ^testing.T) {
	_, _, code := run(t, []string{})
	testing.expect_value(t, code, 1)
}

@(test)
invalid_interval_exits_1 :: proc(t: ^testing.T) {
	_, _, code := run(t, []string{"abc"})
	testing.expect_value(t, code, 1)
}

@(test)
negative_interval_exits_1 :: proc(t: ^testing.T) {
	_, _, code := run(t, []string{"-1"})
	testing.expect_value(t, code, 2)
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
