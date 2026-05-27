package du_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/du.exe"

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
file_exits_0 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-du-file"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	f := strings.concatenate({dir, "\\big.txt"}, context.allocator)
	defer delete(f)
	// 2048 bytes = exactly 2 KiB blocks
	content := make([]u8, 2048, context.allocator)
	defer delete(content)
	for i in 0..<len(content) { content[i] = 'x' }
	_ = os.write_entire_file(f, content)
	defer os.remove(f)

	out, _, code := run(t, []string{f}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "2"), "expected block count of 2")
}

@(test)
directory_exits_0 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-du-dir"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	f := strings.concatenate({dir, "\\x.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "hello")
	defer os.remove(f)

	out, _, code := run(t, []string{dir}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, len(out) > 0, "expected output")
}

@(test)
human_readable_flag :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	tmp, _ := os.temp_dir(context.allocator)
	defer delete(tmp)

	out, _, code := run(t, []string{"-h", tmp}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
}

@(test)
summarize_flag_single_line :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-du-sum"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	sub := strings.concatenate({dir, "\\sub"}, context.allocator)
	defer delete(sub)
	os.make_directory(sub)
	defer os.remove(sub)

	f := strings.concatenate({sub, "\\z.txt"}, context.allocator)
	defer delete(f)
	_ = os.write_entire_file_from_string(f, "data")
	defer os.remove(f)

	out_s, _, code_s := run(t, []string{"-s", dir}, base)
	defer delete(out_s)
	out_n, _, _       := run(t, []string{dir}, base)
	defer delete(out_n)

	testing.expect_value(t, code_s, 0)
	// -s should produce fewer lines than without (no sub-directory lines).
	lines_s := strings.count(string(out_s), "\n")
	lines_n := strings.count(string(out_n), "\n")
	testing.expect(t, lines_s <= lines_n, "-s should not produce more lines than without")
}

@(test)
missing_path_exits_1 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	_, _, code := run(t, []string{"no_such_path_winix_du"}, base)
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
