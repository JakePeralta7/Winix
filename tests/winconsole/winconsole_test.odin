package winconsole_test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import win "core:sys/windows"
import "../../internal/winconsole"

@(private="file")
make_pipe_writer_to_temp :: proc(t: ^testing.T) -> (winconsole.Writer, string) {
    base, derr := os.temp_dir(context.allocator)
    testing.expect_value(t, derr, os.ERROR_NONE)
    name := fmt.tprintf("winconsole_test_%d.tmp", time.now()._nsec)
    path := strings.concatenate({strings.trim_suffix(base, "\\"), "\\", name}, context.allocator)
    fh, oerr := os.open(path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
    testing.expect_value(t, oerr, os.ERROR_NONE)
    w := winconsole.Writer{
        handle     = win.HANDLE(os.fd(fh)),
        is_console = false,
    }
    return w, path
}

@(test)
write_string_to_pipe_writes_raw_utf8 :: proc(t: ^testing.T) {
    w, path := make_pipe_writer_to_temp(t)
    defer os.remove(path)
    n, err := winconsole.write_string(w, "hi")
    win.CloseHandle(w.handle)
    testing.expect_value(t, err, winconsole.Error.None)
    testing.expect_value(t, n, 2)
    data, rerr := os.read_entire_file_from_path(path, context.allocator)
    testing.expect_value(t, rerr, os.ERROR_NONE)
    testing.expect_value(t, string(data), "hi")
}
