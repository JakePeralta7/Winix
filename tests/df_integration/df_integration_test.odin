package df_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/df.exe"

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
	out, _, code := run(t, []string{})
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, len(out) > 0, "expected some output")
}

@(test)
no_args_shows_header :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{})
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "Filesystem"), "expected header")
}

@(test)
human_readable_flag :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{"-h"})
	defer delete(out)
	testing.expect_value(t, code, 0)
	// Human-readable output should contain a size suffix.
	s := string(out)
	has_suffix := strings.contains(s, "G") || strings.contains(s, "M") || strings.contains(s, "T")
	testing.expect(t, has_suffix, "expected human-readable size suffix")
}

@(test)
path_arg_exits_0 :: proc(t: ^testing.T) {
	tmp, _ := os.temp_dir(context.allocator)
	defer delete(tmp)
	out, _, code := run(t, []string{tmp})
	defer delete(out)
	testing.expect_value(t, code, 0)
}

@(test)
invalid_path_exits_1 :: proc(t: ^testing.T) {
	_, _, code := run(t, []string{"Z:\\no_such_drive_winix_test\\"})
	testing.expect_value(t, code, 1)
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
