package pkill_integration_test

import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

@(private = "file")
EXE :: "bin/pkill.exe"

@(private = "file")
run :: proc(t: ^testing.T, args: []string) -> (stdout: []byte, stderr: []byte, code: int) {
	full := make([]string, 1 + len(args), context.temp_allocator)
	full[0] = EXE
	for a, i in args {
		full[1+i] = a
	}
	state, out, errb, err := os.process_exec(
		os.Process_Desc{command = full},
		context.allocator,
	)
	if err != nil {
		testing.fail_now(t, "process_exec failed")
	}
	return out, errb, state.exit_code
}

@(test)
kills_named_process :: proc(t: ^testing.T) {
	victim, perr := os.process_start(os.Process_Desc{
		command = []string{"ping", "-n", "30", "127.0.0.1"},
	})
	if perr != nil {
		testing.fail_now(t, "could not start ping process")
	}

	time.sleep(200 * time.Millisecond)

	_, _, code := run(t, []string{"ping"})
	testing.expect_value(t, code, 0)

	// process should be dead; wait cleans up the handle
	_, _ = os.process_wait(victim)
}

@(test)
dry_run_shows_would_kill :: proc(t: ^testing.T) {
	victim, perr := os.process_start(os.Process_Desc{
		command = []string{"ping", "-n", "30", "127.0.0.1"},
	})
	if perr != nil {
		testing.fail_now(t, "could not start ping process")
	}
	defer {
		_ = os.process_kill(victim)
		_, _ = os.process_wait(victim)
	}

	time.sleep(200 * time.Millisecond)

	out, _, code := run(t, []string{"-n", "ping"})
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "would kill"), "expected 'would kill' in output")
}

@(test)
no_match_exits_1 :: proc(t: ^testing.T) {
	_, errb, code := run(t, []string{"this-process-does-not-exist-xyzzy-winix"})
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(string(errb), "no process found"), "expected 'no process found' on stderr")
}

@(test)
missing_operand_exits_1 :: proc(t: ^testing.T) {
	_, errb, code := run(t, []string{})
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(string(errb), "missing operand"), "expected 'missing operand' on stderr")
}

@(test)
help_exits_0 :: proc(t: ^testing.T) {
	out, _, code := run(t, []string{"--help"})
	defer delete(out)
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(string(out), "Usage"), "expected 'Usage' in output")
}

@(test)
exact_requires_full_name :: proc(t: ^testing.T) {
	victim, perr := os.process_start(os.Process_Desc{
		command = []string{"ping", "-n", "30", "127.0.0.1"},
	})
	if perr != nil {
		testing.fail_now(t, "could not start ping process")
	}
	defer {
		_ = os.process_kill(victim)
		_, _ = os.process_wait(victim)
	}

	time.sleep(200 * time.Millisecond)

	// -x "ping" should NOT match "ping.exe"
	_, errb, code := run(t, []string{"-x", "ping"})
	defer delete(errb)
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(string(errb), "no process found"), "expected no match without .exe suffix")
}
