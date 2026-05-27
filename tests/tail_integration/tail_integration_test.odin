package tail_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/tail.exe"

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
prints_last_n_lines :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-tail-basic"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	file := strings.concatenate({dir, "\\data.txt"}, context.allocator)
	defer delete(file)
	_ = os.write_entire_file_from_string(file, "a\nb\nc\nd\ne\n")

	out, _, code := run(t, []string{"-n", "3", file}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "c\nd\ne\n")
}

@(test)
default_is_ten_lines :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-tail-default"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	file := strings.concatenate({dir, "\\data.txt"}, context.allocator)
	defer delete(file)
	content := "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n"
	_ = os.write_entire_file_from_string(file, content)

	out, _, code := run(t, []string{file}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n")
}

@(test)
short_file_prints_all :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-tail-short"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	file := strings.concatenate({dir, "\\data.txt"}, context.allocator)
	defer delete(file)
	_ = os.write_entire_file_from_string(file, "only\ntwo\n")

	out, _, code := run(t, []string{"-n", "10", file}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect_value(t, string(out), "only\ntwo\n")
}

@(test)
missing_file_exits_1 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	_, errb, code := run(t, []string{"nonexistent_winix_tail.txt"}, base)
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, len(errb) > 0, "expected error message on stderr")
}

@(test)
missing_operand_exits_1 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	_, errb, code := run(t, []string{}, base)
	defer delete(errb)
	testing.expect_value(t, code, 1)
}

@(test)
help_exits_0 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	out, _, code := run(t, []string{"--help"}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, len(out) > 0, "expected usage on stdout")
}
