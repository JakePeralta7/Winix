# Winix

Windows ports of classic Unix command-line tools, written in Odin, calling the Windows API directly.

## Status

- `pwd` — implemented.

More tools to follow in the same `cmd/<name>/` pattern.

## Build

Prerequisites: Odin compiler on `PATH`, Windows 10+, `windows_amd64`.

```cmd
build.bat
```

or

```powershell
.\build.ps1
```

Binaries land in `.\bin\`.

## Test

```cmd
test.bat
```

Runs unit tests for the internal packages, then builds, then runs integration tests against the built `bin\pwd.exe`.

## Layout

- `cmd/<tool>/` — one directory per binary.
- `internal/cliflag/` — minimal flag parser.
- `internal/winpath/` — cwd and `%PWD%` logic.
- `internal/winconsole/` — UTF-8 / UTF-16 aware stdout writer.
- `tests/<package>/` — `core:testing` tests, one directory per package.

## License

See `LICENSE`.
