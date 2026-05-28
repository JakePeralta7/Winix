package sort_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/sort.exe"

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
sorts_alphabetically :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-sort-alpha"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	f := strings.concatenate({dir, "\\a.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "banana\napple\ncherry\n")

	out, _, code := run(t, []string{f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "apple\nbanana\ncherry\n")
}

@(test)
reverse_flag :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-sort-rev"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	f := strings.concatenate({dir, "\\b.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "b\na\nc\n")

	out, _, code := run(t, []string{"-r", f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "c\nb\na\n")
}

@(test)
unique_flag :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-sort-uniq"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	f := strings.concatenate({dir, "\\c.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "a\nb\na\nc\nb\n")

	out, _, code := run(t, []string{"-u", f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "a\nb\nc\n")
}

@(test)
numeric_sort :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-sort-num"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	f := strings.concatenate({dir, "\\d.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "10\n2\n20\n1\n")

	out, _, code := run(t, []string{"-n", f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "1\n2\n10\n20\n")
}

@(test)
ignore_case_sort :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-sort-fold"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	f := strings.concatenate({dir, "\\e.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "Banana\napple\nCherry\n")

	out, _, code := run(t, []string{"-f", f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "apple\nBanana\nCherry\n")
}

@(test)
multiple_files_concatenated :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-sort-multi"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	f1 := strings.concatenate({dir, "\\f1.txt"}, context.allocator)
	defer delete(f1)
	f2 := strings.concatenate({dir, "\\f2.txt"}, context.allocator)
	defer delete(f2)
	_ = os.write_entire_file_from_string(f1, "c\na\n")
	_ = os.write_entire_file_from_string(f2, "b\nd\n")

	out, _, code := run(t, []string{f1, f2}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "a\nb\nc\nd\n")
}

@(test)
missing_file_exits_1 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	_, errb, code := run(t, []string{"nonexistent_winix_sort.txt"}, base)
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, len(errb) > 0, "expected error message on stderr")
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
