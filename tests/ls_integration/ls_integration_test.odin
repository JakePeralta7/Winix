package ls_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/ls.exe"

@(private = "file")
run :: proc(t: ^testing.T, args: []string, cwd: string) -> (stdout: []byte, stderr: []byte, code: int) {
	full := make([]string, 1 + len(args), context.temp_allocator)
	full[0] = EXE
	for a, i in args {
		full[1+i] = a
	}
	state, out, errb, err := os.process_exec(
		os.Process_Desc{command = full, working_dir = cwd},
		context.allocator,
	)
	if err != nil {
		testing.fail_now(t, "process_exec failed")
	}
	return out, errb, state.exit_code
}

@(test)
lists_files_in_dir :: proc(t: ^testing.T) {
	base, _ := os.temp_dir(context.allocator)
	defer delete(base)
	dir := strings.concatenate({strings.trim_suffix(base, "\\"), "\\winix-ls-basic"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	file := strings.concatenate({dir, "\\hello.txt"}, context.allocator)
	defer delete(file)
	_ = os.write_entire_file_from_string(file, "hi")
	defer os.remove(file)

	out, _, code := run(t, []string{}, dir)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "hello.txt"), "expected hello.txt in output")
}

@(test)
dot_entries_hidden_by_default :: proc(t: ^testing.T) {
	base, _ := os.temp_dir(context.allocator)
	defer delete(base)
	dir := strings.concatenate({strings.trim_suffix(base, "\\"), "\\winix-ls-dot"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	out, _, code := run(t, []string{}, dir)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, !strings.contains(string(out), ".\r\n"), "expected . to be hidden by default")
}

@(test)
all_flag_shows_dot_entries :: proc(t: ^testing.T) {
	base, _ := os.temp_dir(context.allocator)
	defer delete(base)
	dir := strings.concatenate({strings.trim_suffix(base, "\\"), "\\winix-ls-all"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	out, _, code := run(t, []string{"-a"}, dir)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), ".\r\n") || strings.contains(string(out), ".\r\n"), "expected . in -a output")
	testing.expect(t, strings.contains(string(out), ".."), "expected .. in -a output")
}

@(test)
long_format_contains_date :: proc(t: ^testing.T) {
	base, _ := os.temp_dir(context.allocator)
	defer delete(base)
	dir := strings.concatenate({strings.trim_suffix(base, "\\"), "\\winix-ls-long"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	file := strings.concatenate({dir, "\\data.txt"}, context.allocator)
	defer delete(file)
	_ = os.write_entire_file_from_string(file, "content")
	defer os.remove(file)

	out, _, code := run(t, []string{"-l"}, dir)
	defer delete(out)
	testing.expect_value(t, code, 0)
	// Long format should contain a year (4 digits followed by -)
	testing.expect(t, strings.contains(string(out), "202"), "expected year in long format output")
	testing.expect(t, strings.contains(string(out), "data.txt"), "expected filename in long format output")
}

@(test)
path_argument_lists_that_dir :: proc(t: ^testing.T) {
	base, _ := os.temp_dir(context.allocator)
	defer delete(base)
	dir := strings.concatenate({strings.trim_suffix(base, "\\"), "\\winix-ls-path"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	file := strings.concatenate({dir, "\\target.txt"}, context.allocator)
	defer delete(file)
	_ = os.write_entire_file_from_string(file, "x")
	defer os.remove(file)

	// Run from a different cwd, pass the dir as argument
	tmp, _ := os.temp_dir(context.allocator)
	defer delete(tmp)
	out, _, code := run(t, []string{dir}, strings.trim_suffix(tmp, "\\"))
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "target.txt"), "expected target.txt in output")
}

@(test)
nonexistent_path_exits_1 :: proc(t: ^testing.T) {
	tmp, _ := os.temp_dir(context.allocator)
	defer delete(tmp)
	cwd := strings.trim_suffix(tmp, "\\")
	_, errb, code := run(t, []string{"no-such-dir-xyz-winix"}, cwd)
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(string(errb), "cannot access"), "expected 'cannot access' in stderr")
}

@(test)
help_exits_0_with_usage :: proc(t: ^testing.T) {
	tmp, _ := os.temp_dir(context.allocator)
	defer delete(tmp)
	cwd := strings.trim_suffix(tmp, "\\")
	out, _, code := run(t, []string{"--help"}, cwd)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "Usage:"), "expected 'Usage:' in help output")
}

@(test)
version_exits_0_with_prefix :: proc(t: ^testing.T) {
	tmp, _ := os.temp_dir(context.allocator)
	defer delete(tmp)
	cwd := strings.trim_suffix(tmp, "\\")
	out, _, code := run(t, []string{"--version"}, cwd)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.has_prefix(string(out), "ls (winix) "), "expected 'ls (winix) ' prefix")
}

@(test)
unknown_flag_exits_2 :: proc(t: ^testing.T) {
	tmp, _ := os.temp_dir(context.allocator)
	defer delete(tmp)
	cwd := strings.trim_suffix(tmp, "\\")
	_, errb, code := run(t, []string{"-Z"}, cwd)
	defer delete(errb)
	testing.expect_value(t, code, 2)
	testing.expect(t, strings.contains(string(errb), "unknown option"), "expected 'unknown option' in stderr")
}
