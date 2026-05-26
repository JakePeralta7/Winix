package pwd_integration_test

import "core:os"
import "core:strings"
import "core:testing"

@(private="file")
EXE :: "bin/pwd.exe"

@(private="file")
run :: proc(t: ^testing.T, args: []string, cwd: string) -> (stdout: []byte, stderr: []byte, code: int) {
    full := make([]string, 1 + len(args), context.temp_allocator)
    full[0] = EXE
    for a, i in args {
        full[1+i] = a
    }
    desc := os.Process_Desc{
        command     = full,
        working_dir = cwd,
    }
    state, out, errb, err := os.process_exec(desc, context.allocator)
    if err != nil {
        testing.fail_now(t, "process_exec failed")
    }
    return out, errb, state.exit_code
}

@(test)
prints_cwd_with_crlf :: proc(t: ^testing.T) {
    tmp_base, _ := os.temp_dir(context.allocator)
    defer delete(tmp_base)
    tmp := strings.trim_suffix(tmp_base, "\\")
    out, _, code := run(t, []string{}, tmp)
    testing.expect_value(t, code, 0)
    line := string(out)
    testing.expect(t, strings.has_suffix(line, "\r\n"), "expected CRLF terminator")
    trimmed := strings.trim_suffix(line, "\r\n")
    testing.expect(t, strings.equal_fold(trimmed, tmp), "stdout did not match cwd (case-insensitive)")
}
