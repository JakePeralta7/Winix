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

@(test)
use_percent_is_not_zero_padded :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{})
	defer delete(out)
	testing.expect_value(t, code, 0)

	lines := strings.split_lines(string(out), context.temp_allocator)
	for line in lines {
		if len(line) == 0 || strings.has_prefix(line, "Filesystem") { continue }
		pct := strings.last_index_byte(line, '%')
		if pct < 1 { continue }

		start := pct
		for start > 0 && line[start-1] >= '0' && line[start-1] <= '9' {
			start -= 1
		}
		digits := line[start:pct]
		if len(digits) > 1 {
			testing.expect(t, digits[0] != '0', "use percentage should be space-padded, not zero-padded")
		}
	}
}

@(test)
print_type_with_path_shows_filesystem :: proc(t: ^testing.T) {
	tmp, _ := os.temp_dir(context.allocator)
	defer delete(tmp)

	out, _, code := run(t, []string{"-T", tmp})
	defer delete(out)
	testing.expect_value(t, code, 0)

	lines := strings.split_lines(string(out), context.temp_allocator)
	testing.expect(t, len(lines) >= 2, "expected header and one data row")
	if len(lines) < 2 { return }

	fields, err := strings.fields(lines[1], context.temp_allocator)
	if err != nil { testing.fail_now(t, "strings.fields failed") }
	testing.expect(t, len(fields) >= 2, "expected filesystem type column")
	if len(fields) >= 2 {
		testing.expect(t, len(fields[1]) > 0, "expected non-empty filesystem type")
	}
}
