package which_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/which.exe"

@(private = "file")
run :: proc(t: ^testing.T, args: []string, cwd: string = "") -> (stdout: []byte, stderr: []byte, code: int) {
	full := make([]string, 1 + len(args), context.temp_allocator)
	full[0] = EXE
	for a, i in args {
		full[1+i] = a
	}
	desc := os.Process_Desc{
		command     = full,
		working_dir = cwd,
	}
	state, out, errb, err := os.process_exec(desc, context.allocator)
	if err != nil {
		testing.fail_now(t, "process_exec failed")
	}
	return out, errb, state.exit_code
}

@(private = "file")
run_with_path :: proc(t: ^testing.T, args: []string, extra_path_dirs: []string) -> (stdout: []byte, stderr: []byte, code: int) {
	full := make([]string, 1 + len(args), context.temp_allocator)
	full[0] = EXE
	for a, i in args {
		full[1+i] = a
	}

	// Build a new PATH prepending extra dirs
	old_path := os.get_env("PATH", context.temp_allocator)
	prefix   := strings.join(extra_path_dirs, ";", context.temp_allocator)
	new_path := strings.concatenate({"PATH=", prefix, ";", old_path}, context.temp_allocator)

	// Clone the current environment and replace PATH
	raw_env, _ := os.environ(context.temp_allocator)
	env     := make([dynamic]string, 0, len(raw_env) + 1, context.temp_allocator)
	for e in raw_env {
		if len(e) >= 5 && strings.equal_fold(e[:5], "PATH=") { continue }
		append(&env, e)
	}
	append(&env, new_path)

	desc := os.Process_Desc{
		command = full,
		env     = env[:],
	}
	state, out, errb, err := os.process_exec(desc, context.allocator)
	if err != nil {
		testing.fail_now(t, "process_exec failed")
	}
	return out, errb, state.exit_code
}

@(test)
finds_cmd_exe :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{"cmd"})
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(strings.to_lower(string(out), context.temp_allocator), "cmd.exe"), "expected cmd.exe in output")
}

@(test)
not_found_exits_1 :: proc(t: ^testing.T) {
	_, errb, code := run(t, []string{"this-command-does-not-exist-xyz-winix"})
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(string(errb), "not found"), "expected 'not found' on stderr")
}

@(test)
multiple_args_partial_miss_exits_1 :: proc(t: ^testing.T) {
	out, errb, code := run(t, []string{"cmd", "this-command-does-not-exist-xyz-winix"})
	defer delete(out)
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(strings.to_lower(string(out), context.temp_allocator), "cmd.exe"), "expected cmd.exe on stdout")
	testing.expect(t, strings.contains(string(errb), "not found"), "expected 'not found' on stderr")
}

@(test)
output_ends_with_crlf :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{"cmd"})
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.has_suffix(string(out), "\r\n"), "expected CRLF line ending")
}

@(test)
no_args_exits_1 :: proc(t: ^testing.T) {
	_, _, code := run(t, []string{})
	testing.expect_value(t, code, 1)
}

@(test)
help_prints_usage_exit_0 :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{"--help"})
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "Usage:"), "expected 'Usage:' in help output")
}

@(test)
version_prints_string_exit_0 :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{"--version"})
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.has_prefix(string(out), "which (winix) "), "expected 'which (winix) ...' prefix")
}

@(test)
unknown_flag_exits_2_with_stderr :: proc(t: ^testing.T) {
	_, errb, code := run(t, []string{"-X"})
	defer delete(errb)
	testing.expect_value(t, code, 2)
	testing.expect(t, strings.contains(string(errb), "unknown option"), "expected 'unknown option' on stderr")
}

@(test)
all_flag_returns_all_matches :: proc(t: ^testing.T) {
	base, _ := os.temp_dir(context.allocator)
	defer delete(base)
	b := strings.trim_suffix(base, "\\")

	dir1 := strings.concatenate({b, "\\winix-which-a1"}, context.allocator)
	defer delete(dir1)
	dir2 := strings.concatenate({b, "\\winix-which-a2"}, context.allocator)
	defer delete(dir2)
	os.make_directory(dir1)
	defer os.remove(dir1)
	os.make_directory(dir2)
	defer os.remove(dir2)

	exe1 := strings.concatenate({dir1, "\\fakewhich.exe"}, context.allocator)
	defer delete(exe1)
	exe2 := strings.concatenate({dir2, "\\fakewhich.exe"}, context.allocator)
	defer delete(exe2)
	_ = os.write_entire_file_from_string(exe1, "fake")
	defer os.remove(exe1)
	_ = os.write_entire_file_from_string(exe2, "fake")
	defer os.remove(exe2)

	out, _, code := run_with_path(t, []string{"-a", "fakewhich"}, []string{dir1, dir2})
	defer delete(out)
	testing.expect_value(t, code, 0)
	lines := strings.split(strings.trim_suffix(string(out), "\r\n"), "\r\n", context.temp_allocator)
	testing.expect(t, len(lines) >= 2, "expected at least 2 results with -a")
}

@(test)
without_all_flag_returns_first_only :: proc(t: ^testing.T) {
	base, _ := os.temp_dir(context.allocator)
	defer delete(base)
	b := strings.trim_suffix(base, "\\")

	dir1 := strings.concatenate({b, "\\winix-which-f1"}, context.allocator)
	defer delete(dir1)
	dir2 := strings.concatenate({b, "\\winix-which-f2"}, context.allocator)
	defer delete(dir2)
	os.make_directory(dir1)
	defer os.remove(dir1)
	os.make_directory(dir2)
	defer os.remove(dir2)

	exe1 := strings.concatenate({dir1, "\\fakefirst.exe"}, context.allocator)
	defer delete(exe1)
	exe2 := strings.concatenate({dir2, "\\fakefirst.exe"}, context.allocator)
	defer delete(exe2)
	_ = os.write_entire_file_from_string(exe1, "fake")
	defer os.remove(exe1)
	_ = os.write_entire_file_from_string(exe2, "fake")
	defer os.remove(exe2)

	out, _, code := run_with_path(t, []string{"fakefirst"}, []string{dir1, dir2})
	defer delete(out)
	testing.expect_value(t, code, 0)
	lines := strings.split(strings.trim_suffix(string(out), "\r\n"), "\r\n", context.temp_allocator)
	testing.expect_value(t, len(lines), 1)
	testing.expect(t, strings.contains(lines[0], dir1), "expected first dir in result")
}
