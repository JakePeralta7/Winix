package mv_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/mv.exe"

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
renames_file :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-mv-rename"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	src := strings.concatenate({dir, "\\src.txt"}, context.allocator)
	defer delete(src)
	dst := strings.concatenate({dir, "\\dst.txt"}, context.allocator)
	defer delete(dst)
	_ = os.write_entire_file_from_string(src, "hello")

	_, _, code := run(t, []string{src, dst}, base)
	testing.expect_value(t, code, 0)
	testing.expect(t, !os.exists(src), "source should no longer exist")
	testing.expect(t, os.exists(dst), "destination should exist")
}

@(test)
moves_file_into_directory :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-mv-intodir"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	sub := strings.concatenate({dir, "\\sub"}, context.allocator)
	defer delete(sub)
	os.make_directory(sub)

	src := strings.concatenate({dir, "\\file.txt"}, context.allocator)
	defer delete(src)
	_ = os.write_entire_file_from_string(src, "data")

	_, _, code := run(t, []string{src, sub}, base)
	testing.expect_value(t, code, 0)
	testing.expect(t, !os.exists(src), "source should no longer exist")

	dst := strings.concatenate({sub, "\\file.txt"}, context.allocator)
	defer delete(dst)
	testing.expect(t, os.exists(dst), "file should be inside target directory")
}

@(test)
overwrites_existing_by_default :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-mv-overwrite"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	src := strings.concatenate({dir, "\\src.txt"}, context.allocator)
	defer delete(src)
	dst := strings.concatenate({dir, "\\dst.txt"}, context.allocator)
	defer delete(dst)
	_ = os.write_entire_file_from_string(src, "new")
	_ = os.write_entire_file_from_string(dst, "old")

	_, _, code := run(t, []string{src, dst}, base)
	testing.expect_value(t, code, 0)
	// Source is gone; destination still exists (was overwritten).
	testing.expect(t, !os.exists(src), "source should be gone after overwrite")
	testing.expect(t, os.exists(dst), "destination should still exist")
}

@(test)
no_clobber_skips_existing :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-mv-noclobber"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	src := strings.concatenate({dir, "\\src.txt"}, context.allocator)
	defer delete(src)
	dst := strings.concatenate({dir, "\\dst.txt"}, context.allocator)
	defer delete(dst)
	_ = os.write_entire_file_from_string(src, "new")
	_ = os.write_entire_file_from_string(dst, "old")

	_, _, code := run(t, []string{"-n", src, dst}, base)
	testing.expect_value(t, code, 0)

	// src should still exist (was not moved), dst still exists.
	testing.expect(t, os.exists(src), "source should remain when no-clobber is set")
	testing.expect(t, os.exists(dst), "destination should still exist")
}

@(test)
missing_source_exits_1 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	_, errb, code := run(t, []string{"nonexistent_winix_mv.txt", "also_nonexistent.txt"}, base)
	defer delete(errb)
	testing.expect_value(t, code, 1)
}

@(test)
missing_destination_operand_exits_1 :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)

	_, errb, code := run(t, []string{"only_one_arg.txt"}, base)
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
