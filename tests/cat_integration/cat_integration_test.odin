package cat_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/cat.exe"

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

@(private = "file")
temp_base :: proc() -> string {
	tmp, _ := os.temp_dir(context.allocator)
	return strings.trim_suffix(tmp, "\\")
}

@(test)
prints_single_file :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-cat-single"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	file := strings.concatenate({dir, "\\hello.txt"}, context.allocator)
	defer delete(file)
	_ = os.write_entire_file_from_string(file, "hello")
	defer os.remove(file)

	out, _, code := run(t, []string{file}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "hello")
}

@(test)
concatenates_multiple_files_in_order :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-cat-multi"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	one := strings.concatenate({dir, "\\one.txt"}, context.allocator)
	defer delete(one)
	two := strings.concatenate({dir, "\\two.txt"}, context.allocator)
	defer delete(two)
	_ = os.write_entire_file_from_string(one, "abc")
	defer os.remove(one)
	_ = os.write_entire_file_from_string(two, "123")
	defer os.remove(two)

	out, _, code := run(t, []string{one, two}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "abc123")
}

@(test)
missing_operand_exits_1 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	_, errb, code := run(t, []string{}, base)
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(string(errb), "missing operand"), "expected 'missing operand' in stderr")
}

@(test)
missing_file_exits_1_with_error :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	fake := strings.concatenate({base, "\\does-not-exist-cat-winix"}, context.allocator)
	defer delete(fake)

	_, errb, code := run(t, []string{fake}, base)
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(string(errb), "No such file or directory"), "expected not found message")
}

@(test)
prints_existing_even_if_later_file_missing :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-cat-partial"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	file := strings.concatenate({dir, "\\ok.txt"}, context.allocator)
	defer delete(file)
	_ = os.write_entire_file_from_string(file, "ok")
	defer os.remove(file)
	fake := strings.concatenate({dir, "\\missing.txt"}, context.allocator)
	defer delete(fake)

	out, errb, code := run(t, []string{file, fake}, base)
	defer delete(out)
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect_value(t, string(out), "ok")
	testing.expect(t, strings.contains(string(errb), "No such file or directory"), "expected missing-file message")
}

@(test)
help_exits_0_with_usage :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	out, _, code := run(t, []string{"--help"}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "Usage:"), "expected 'Usage:' in help output")
}

@(test)
version_exits_0_with_prefix :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	out, _, code := run(t, []string{"--version"}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.has_prefix(string(out), "cat (winix) "), "expected 'cat (winix) ' prefix")
}

@(test)
unknown_flag_exits_2 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	_, errb, code := run(t, []string{"-Z"}, base)
	defer delete(errb)
	testing.expect_value(t, code, 2)
	testing.expect(t, strings.contains(string(errb), "unknown option"), "expected unknown option on stderr")
}
