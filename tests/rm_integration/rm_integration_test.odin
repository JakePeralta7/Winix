package rm_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/rm.exe"

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

// temp_base returns the system temp directory without a trailing backslash.
@(private = "file")
temp_base :: proc() -> string {
	tmp, _ := os.temp_dir(context.allocator)
	return strings.trim_suffix(tmp, "\\")
}

@(test)
removes_single_file :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-rm-file"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	file := strings.concatenate({dir, "\\hello.txt"}, context.allocator)
	defer delete(file)
	_ = os.write_entire_file_from_string(file, "content")

	_, _, code := run(t, []string{file}, base)
	testing.expect_value(t, code, 0)
	testing.expect(t, !os.exists(file), "file should have been removed")
}

@(test)
removes_dir_recursively :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-rm-rdir"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)

	sub := strings.concatenate({dir, "\\sub"}, context.allocator)
	defer delete(sub)
	os.make_directory(sub)

	file := strings.concatenate({sub, "\\data.txt"}, context.allocator)
	defer delete(file)
	_ = os.write_entire_file_from_string(file, "data")

	_, _, code := run(t, []string{"-r", dir}, base)
	testing.expect_value(t, code, 0)
	testing.expect(t, !os.exists(dir), "directory tree should have been removed")
}

@(test)
dir_without_recursive_exits_1 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-rm-norecurse"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	_, errb, code := run(t, []string{dir}, base)
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(string(errb), "Is a directory"), "expected 'Is a directory' on stderr")
}

@(test)
nonexistent_without_force_exits_1 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	fake := strings.concatenate({base, "\\does-not-exist-xyz"}, context.allocator)
	defer delete(fake)

	_, errb, code := run(t, []string{fake}, base)
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(string(errb), "No such file or directory"), "expected not-found message on stderr")
}

@(test)
nonexistent_with_force_exits_0 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	fake := strings.concatenate({base, "\\does-not-exist-xyz"}, context.allocator)
	defer delete(fake)

	_, _, code := run(t, []string{"-f", fake}, base)
	testing.expect_value(t, code, 0)
}

@(test)
no_operand_exits_1 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	_, errb, code := run(t, []string{}, base)
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(string(errb), "missing operand"), "expected 'missing operand' on stderr")
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
	testing.expect(t, strings.has_prefix(string(out), "rm (winix) "), "expected 'rm (winix) ...' prefix")
}

@(test)
unknown_flag_exits_2 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	_, errb, code := run(t, []string{"-Z"}, base)
	defer delete(errb)
	testing.expect_value(t, code, 2)
	testing.expect(t, strings.contains(string(errb), "unknown option"), "expected 'unknown option' on stderr")
}

@(test)
verbose_prints_removed :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-rm-verbose"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove(dir)

	file := strings.concatenate({dir, "\\note.txt"}, context.allocator)
	defer delete(file)
	_ = os.write_entire_file_from_string(file, "hi")

	out, _, code := run(t, []string{"-v", file}, base)
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "removed '"), "expected 'removed ...' in verbose output")
}
