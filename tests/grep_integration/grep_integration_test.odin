package grep_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/grep.exe"

@(private = "file")
run :: proc(t: ^testing.T, args: []string, cwd: string) -> (stdout: []byte, stderr: []byte, code: int) {
	full := make([]string, 1 + len(args), context.temp_allocator)
	full[0] = EXE
	for a, i in args { full[1+i] = a }
	state, out, errb, err := os.process_exec(
		os.Process_Desc{command = full, working_dir = cwd},
		context.allocator,
	)
	if err != nil { testing.fail_now(t, "process_exec failed") }
	return out, errb, state.exit_code
}

@(private = "file")
temp_base :: proc() -> string {
	tmp, _ := os.temp_dir(context.allocator)
	return strings.trim_suffix(tmp, "\\")
}

@(test)
match_found_exits_0 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-grep-basic"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	f := strings.concatenate({dir, "\\hay.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "needle\nhaystack\n")
	defer os.remove(f)

	out, _, code := run(t, []string{"needle", f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "needle"), "expected matching line in output")
}

@(test)
no_match_exits_1 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-grep-nomatch"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	f := strings.concatenate({dir, "\\data.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "hello world\n")
	defer os.remove(f)

	_, _, code := run(t, []string{"zzz", f}, base)
	testing.expect_value(t, code, 1)
}

@(test)
ignore_case_flag :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-grep-icase"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	f := strings.concatenate({dir, "\\case.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "Hello World\n")
	defer os.remove(f)

	out, _, code := run(t, []string{"-i", "hello", f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "Hello"), "expected case-insensitive match")
}

@(test)
invert_flag :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-grep-invert"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	f := strings.concatenate({dir, "\\inv.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "keep\nremove\nkeep2\n")
	defer os.remove(f)

	out, _, code := run(t, []string{"-v", "remove", f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t,  strings.contains(string(out), "keep"),   "expected non-matching lines")
	testing.expect(t, !strings.contains(string(out), "remove"), "should not contain removed line")
}

@(test)
count_flag :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-grep-count"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	f := strings.concatenate({dir, "\\cnt.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "foo\nbar\nfoo\n")
	defer os.remove(f)

	out, _, code := run(t, []string{"-c", "foo", f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "2"), "expected count of 2")
}

@(test)
line_number_flag :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-grep-linenum"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	f := strings.concatenate({dir, "\\ln.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "aaa\nbbb\nccc\n")
	defer os.remove(f)

	out, _, code := run(t, []string{"-n", "bbb", f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "2:"), "expected line number prefix")
}

@(test)
missing_pattern_exits_2 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	_, _, code := run(t, []string{}, base)
	testing.expect_value(t, code, 2)
}

@(test)
help_exits_0 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	_, _, code := run(t, []string{"--help"}, base)
	testing.expect_value(t, code, 0)
}

@(test)
version_exits_0 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	_, _, code := run(t, []string{"--version"}, base)
	testing.expect_value(t, code, 0)
}
