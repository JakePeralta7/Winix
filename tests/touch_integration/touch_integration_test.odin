package touch_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
EXE :: "bin/touch.exe"

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
creates_new_file :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-touch-create"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	file := strings.concatenate({dir, "\\new.txt"}, context.allocator)
	defer delete(file)

	testing.expect(t, !os.exists(file), "file should not exist yet")
	_, _, code := run(t, []string{file}, base)
	testing.expect_value(t, code, 0)
	testing.expect(t, os.exists(file), "file should have been created")
}

@(test)
updates_existing_file :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-touch-update"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	file := strings.concatenate({dir, "\\existing.txt"}, context.allocator)
	defer delete(file)
	_ = os.write_entire_file_from_string(file, "content preserved")

	_, _, code := run(t, []string{file}, base)
	testing.expect_value(t, code, 0)
	// Verify file still exists (touch must not truncate it).
	testing.expect(t, os.exists(file), "file should still exist after touch")
}

@(test)
creates_multiple_files :: proc(t: ^testing.T) {
	base := temp_base()
	defer delete(base)
	dir := strings.concatenate({base, "\\winix-touch-multi"}, context.allocator)
	defer delete(dir)
	os.make_directory(dir)
	defer os.remove_all(dir)

	a := strings.concatenate({dir, "\\a.txt"}, context.allocator)
	defer delete(a)
	b := strings.concatenate({dir, "\\b.txt"}, context.allocator)
	defer delete(b)

	_, _, code := run(t, []string{a, b}, base)
	testing.expect_value(t, code, 0)
	testing.expect(t, os.exists(a), "a.txt should have been created")
	testing.expect(t, os.exists(b), "b.txt should have been created")
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
