package uniq_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/uniq.exe"

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
removes_adjacent_duplicates :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-uniq-basic"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	f := strings.concatenate({dir, "\\a.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "a\na\nb\nb\na\n")

	out, _, code := run(t, []string{f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "a\nb\na\n")
}

@(test)
count_flag :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-uniq-count"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	f := strings.concatenate({dir, "\\b.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "x\nx\nx\ny\n")

	out, _, code := run(t, []string{"-c", f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "3"), "expected count 3 for 'x'")
	testing.expect(t, strings.contains(string(out), "1"), "expected count 1 for 'y'")
}

@(test)
repeated_flag :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-uniq-dup"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	f := strings.concatenate({dir, "\\c.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "a\na\nb\nc\n")

	out, _, code := run(t, []string{"-d", f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "a\n")
}

@(test)
unique_flag :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-uniq-uniq"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	f := strings.concatenate({dir, "\\d.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "a\na\nb\nc\n")

	out, _, code := run(t, []string{"-u", f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "b\nc\n")
}

@(test)
ignore_case_flag :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-uniq-ci"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	f := strings.concatenate({dir, "\\e.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "Hello\nhello\nWORLD\nworld\n")

	out, _, code := run(t, []string{"-i", f}, base)
	defer delete(out)
	// "Hello"/"hello" collapse to one run; "WORLD"/"world" collapse to one run.
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "Hello\nWORLD\n")
}

@(test)
missing_file_exits_1 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	_, errb, code := run(t, []string{"nonexistent_winix_uniq.txt"}, base)
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, len(errb) > 0, "expected error message on stderr")
}

@(test)
extra_operand_exits_2 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-uniq-extra"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	f1 := strings.concatenate({dir, "\\x.txt"}, context.allocator)
	defer delete(f1)
	f2 := strings.concatenate({dir, "\\y.txt"}, context.allocator)
	defer delete(f2)
	_ = os.write_entire_file_from_string(f1, "a\n")
	_ = os.write_entire_file_from_string(f2, "b\n")

	_, errb, code := run(t, []string{f1, f2}, base)
	defer delete(errb)
	testing.expect_value(t, code, 2)
}

@(test)
help_flag :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	out, _, code := run(t, []string{"--help"}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "Usage:"), "expected usage in help output")
}

@(test)
unknown_flag_exits_2 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	_, errb, code := run(t, []string{"--unknown-flag"}, base)
	defer delete(errb)
	testing.expect_value(t, code, 2)
}
