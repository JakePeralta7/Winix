package wc_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/wc.exe"

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
counts_lines_words_bytes :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-wc-basic"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	f := strings.concatenate({dir, "\\a.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "hello world\nfoo bar\n")
	defer os.remove(f)

	out, _, code := run(t, []string{f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	s := strings.trim_space(string(out))
	// Output should contain the three counts plus the filename.
	testing.expect(t, strings.contains(s, "2"),  "expected line count 2")
	testing.expect(t, strings.contains(s, "4"),  "expected word count 4")
	testing.expect(t, strings.contains(s, "20"), "expected byte count 20")
}

@(test)
lines_flag :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-wc-lines"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	f := strings.concatenate({dir, "\\b.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "a\nb\nc\n")
	defer os.remove(f)

	out, _, code := run(t, []string{"-l", f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "3"), "expected 3 lines")
}

@(test)
multiple_files_shows_total :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-wc-total"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	f1 := strings.concatenate({dir, "\\c1.txt"}, context.allocator)
	f2 := strings.concatenate({dir, "\\c2.txt"}, context.allocator)
	defer { delete(f1); delete(f2) }
	_ = os.write_entire_file_from_string(f1, "x\n")
	_ = os.write_entire_file_from_string(f2, "y\n")
	defer { os.remove(f1); os.remove(f2) }

	out, _, code := run(t, []string{"-l", f1, f2}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "total"), "expected 'total' line")
}

@(test)
missing_file_exits_1 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	_, _, code := run(t, []string{"no_such_file_xyz.txt"}, base)
	testing.expect_value(t, code, 1)
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
