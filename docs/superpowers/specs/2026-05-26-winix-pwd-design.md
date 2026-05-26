# Winix — `pwd` (initial binary) — Design

**Date:** 2026-05-26
**Status:** Approved
**Scope:** Bootstrap the Winix repo and ship the first binary, `pwd.exe`. Establish the layout, shared internal packages, build scripts, and test harness that subsequent Unix-port binaries will reuse.

## Goals

- Set up a multi-binary Odin monorepo (`cmd/<name>/` per binary, shared code in `internal/`) that builds Windows executables via the Windows API (`core:sys/windows`).
- Ship `pwd.exe`: a practical Windows port of the Unix `pwd` utility — honors `-L`/`-P` and the `PWD` environment variable, but emits Windows-native paths (backslashes, drive letter).
- Render non-ASCII paths (specifically Hebrew) correctly both on console and when redirected to pipes/files.
- Establish reusable internal packages and a build/test workflow so adding the next binary is incremental.

## Non-goals

- Cross-platform support. Target is `windows_amd64` only.
- Full POSIX-shell compatibility (no `-L` matching POSIX literal-output format; we emit native paths).
- Performance tuning beyond `odin build -o:speed`.
- A "library" surface for embedding `pwd` logic in other Odin programs. Each binary is a standalone tool.
- A multicall (busybox-style) single binary. Each tool is its own `.exe`.

## Repository layout

```
Winix/
├── cmd/
│   └── pwd/
│       └── main.odin              # entry: parse flags, call winpath, print
├── internal/
│   ├── winconsole/                # stdout/stderr writer
│   │   └── winconsole.odin
│   ├── winpath/                   # cwd + PWD logic
│   │   └── winpath.odin
│   └── cliflag/                   # minimal flag parser
│       └── cliflag.odin
├── tests/
│   ├── cliflag/                   # unit tests
│   ├── winconsole/                # unit tests (pipe path)
│   ├── winpath/                   # unit tests
│   └── pwd_integration/           # spawns bin/pwd.exe in temp dirs
├── bin/                           # build output (gitignored)
├── build.bat                      # Windows cmd build
├── build.ps1                      # PowerShell build
├── test.bat                       # run unit + integration tests
├── test.ps1
├── .gitignore
├── LICENSE
└── README.md
```

Dependency rules:

- Each `cmd/<name>/` may import any `internal/*` package and `core:*`.
- `cmd/*` packages MUST NOT import other `cmd/*` packages.
- `internal/*` packages may import `core:*` only — no cross-`internal` deps for now.

Toolchain: latest stable Odin compiler with `core:sys/windows`, `core:testing`, and `core:os` (the process API — `os.process_exec` — is used by integration tests for spawn + capture).

## `pwd` behavior

**Synopsis:** `pwd [-L | -P] [--help] [--version]`

### Flags

- `-L` (default) — logical. Honor `%PWD%` when it resolves to the same directory as the actual current working directory.
- `-P` — physical. Resolve symlinks, junctions, and other reparse points via `GetFinalPathNameByHandleW`; strip a leading `\\?\` prefix from the result (UNC `\\?\UNC\server\share\...` is reduced to `\\server\share\...`).
- `-L` and `-P` may both be passed; the **last one wins** (matching POSIX `pwd` semantics).
- `--help` — print usage to stdout, exit 0.
- `--version` — print `pwd (winix) <version>` to stdout, exit 0. `<version>` is a hardcoded string constant in `cmd/pwd/main.odin` (initial value `0.1.0`); we will switch to a build-time injected value when we add release tagging.
- Unknown flag — error to stderr, exit 2.

### Path format (Windows-native)

- Backslash separators (`C:\Users\foo`).
- Drive letter uppercase.
- No trailing backslash, except for the root of a drive or share (`C:\`, `\\server\share\`).
- UNC paths kept as `\\server\share\...`.
- Output is UTF-8 (see *Output encoding*); on the console rendered via `WriteConsoleW` so the byte/encoding distinction is invisible to the terminal.

### `-L` validation rule

The value of `%PWD%` is accepted iff all of the following hold:

1. It is non-empty and absolute (matches `^[A-Za-z]:\\` or `^\\\\`).
2. `CreateFileW` opens it successfully with `FILE_FLAG_BACKUP_SEMANTICS` (required for directory handles).
3. `GetFileInformationByHandle` on that handle and on a handle opened against the actual current working directory return identical `dwVolumeSerialNumber`, `nFileIndexHigh`, and `nFileIndexLow`.

If any condition fails, fall back silently to the physical path.

### Exit codes

- `0` — success.
- `1` — runtime error (cwd unreadable, write to stdout failed, OOM).
- `2` — usage error (unknown flag, extra positional argument).

### Argument handling

- Stdin is ignored.
- Any positional argument is rejected with exit 2.

## Components

### `internal/cliflag`

Pure function, no I/O. Takes argv (without program name) plus a spec describing allowed flags; returns a parsed struct, an error enum, and the offending token (for diagnostics).

```odin
package cliflag

Parsed :: struct {
    physical: bool,     // -P set; with multiple -L/-P, last wins
    help:     bool,
    version:  bool,
    rest:     []string, // positional args
}

Parse_Error :: enum {
    None,
    Unknown_Flag,
    Bad_Combo,
}

Flag_Kind :: enum { Bool_Last_Wins } // grow as later tools need more shapes
Flag_Def  :: struct {
    long:  string,  // e.g. "help", "" if short-only
    short: rune,    // e.g. 'L', 0 if long-only
    kind:  Flag_Kind,
    target: ^bool,  // for Bool_Last_Wins, the bool to set
}
Spec :: struct {
    flags: []Flag_Def,
}

parse :: proc(args: []string, spec: Spec) -> (Parsed, Parse_Error, string)
```

The parser is intentionally minimal — just enough for `pwd`. It will grow as later binaries (e.g. `ls`, `cat`) need additional flag shapes; growth is additive (new fields on `Spec`/`Parsed`).

### `internal/winpath`

```odin
package winpath

Error :: enum {
    None,
    GetCwd_Failed,
    Env_Read_Failed,
    Open_Failed,
    Resolve_Failed,
    Encoding_Failed,
}

get_cwd_physical :: proc(allocator := context.allocator) -> (path: string, err: Error)
get_cwd_logical  :: proc(allocator := context.allocator) -> (path: string, err: Error)
```

`get_cwd_physical`:
1. `GetCurrentDirectoryW` (size query → allocate → read).
2. Open handle to that path with `CreateFileW(... FILE_FLAG_BACKUP_SEMANTICS ...)`.
3. `GetFinalPathNameByHandleW` to resolve reparse points.
4. Strip `\\?\` / `\\?\UNC\` prefix; normalize drive letter case and trailing slash.
5. UTF-16 → UTF-8 via `core:sys/windows.utf16_to_utf8`.

`get_cwd_logical`:
1. Read `%PWD%` via `GetEnvironmentVariableW`. If unset/empty → return physical.
2. Apply the `-L` validation rule above. On any failure → return physical.
3. Otherwise normalize the `PWD` value (drive letter case, trailing slash) and return it as UTF-8.

Returned strings are owned by the supplied allocator.

### `internal/winconsole`

```odin
package winconsole

Writer :: struct {
    handle:     win.HANDLE,
    is_console: bool,
}

Error :: enum { None, Write_Failed, Encoding_Failed }

stdout       :: proc() -> Writer
stderr       :: proc() -> Writer
write_string :: proc(w: Writer, s: string) -> (n: int, err: Error)
write_line   :: proc(w: Writer, s: string) -> (n: int, err: Error)  // appends \r\n
fmt_last_error :: proc(code: u32, allocator := context.allocator) -> string
```

- `is_console = (GetFileType(handle) == FILE_TYPE_CHAR)`.
- Console branch: convert UTF-8 → UTF-16 → `WriteConsoleW`. This renders Hebrew (and any other Unicode) correctly regardless of console code page.
- Pipe/file branch: write the raw UTF-8 bytes via `WriteFile`. Redirection to a file produces a valid UTF-8 file.
- `fmt_last_error` wraps `FormatMessageW` (`FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS`, neutral language) and strips trailing CRLF.

### `cmd/pwd/main.odin`

Glue, roughly 40 lines:

1. Build `pwd_spec` with four `Flag_Def`s targeting local `physical`, `help`, `version` bools (plus a sentinel `logical` bool for `-L` whose value is ignored — `physical` reflects last-wins). Then `parsed, perr, tok := cliflag.parse(os.args[1:], pwd_spec)`.
2. Handle `--help` / `--version` → write usage/version to stdout, exit 0.
3. On `perr != .None` or `len(parsed.rest) > 0` → diagnostic to stderr, exit 2.
4. `path, werr := parsed.physical ? winpath.get_cwd_physical() : winpath.get_cwd_logical()`
5. On `werr != .None` → `pwd: <message>` to stderr, exit 1.
6. `winconsole.write_line(stdout, path)`; on failure exit 1.
7. Exit 0.

## Data flow

```
os.args ──► cliflag.parse ──► Parsed{physical}
                                    │
                                    ▼
                     winpath.get_cwd_{logical,physical}
                                    │
            ┌───────────────────────┼───────────────────────┐
            ▼                       ▼                       ▼
  GetEnvironmentVariableW   GetCurrentDirectoryW    CreateFileW + GetFileInfoByHandle
       ("PWD")                                      (identity check, -L only)
                                    │
                                    ▼
                          UTF-16 → UTF-8 (chosen path)
                                    │
                                    ▼
                          winconsole.write_line(stdout)
                                    │
                  ┌─────────────────┴─────────────────┐
                  ▼                                   ▼
         is_console = true                   is_console = false
         UTF-8 → UTF-16 → WriteConsoleW      WriteFile raw UTF-8
                                    │
                                    ▼
                                 exit 0
```

## Error handling

| Source                                  | Caught at | Exit | stderr message                                         |
| --------------------------------------- | --------- | ---- | ------------------------------------------------------ |
| `cliflag.Unknown_Flag`                  | main      | 2    | `pwd: unknown option: <tok>\nTry 'pwd --help'.`        |
| Extra positional arg                    | main      | 2    | `pwd: too many arguments`                              |
| `GetCurrentDirectoryW` returns 0        | winpath   | 1    | `pwd: cannot get current directory: <FormatMessageW>`  |
| `CreateFileW` fails during `-L` check   | winpath   | —    | silent fall back to physical                           |
| `GetFinalPathNameByHandleW` fails (-P)  | winpath   | 1    | `pwd: cannot resolve path: <FormatMessageW>`           |
| UTF-16 → UTF-8 conversion fails         | winpath   | 1    | `pwd: encoding error`                                  |
| `WriteConsoleW` / `WriteFile` fails     | main      | 1    | best-effort write to stderr, then exit                 |
| OOM / allocator failure                 | main      | 1    | `pwd: out of memory`                                   |

**Resource discipline:**
- UTF-16 scratch buffers allocated via `context.temp_allocator`; `free_all(context.temp_allocator)` before exit on every path.
- File handles from `CreateFileW` released via `defer win.CloseHandle(h)`.
- Returned strings use the caller-supplied allocator.

**No panics in the normal flow.** Errors propagate as enum values plus formatted messages. `runtime.assert` is reserved for invariant violations that indicate bugs (e.g., negative length from a Win32 call documented to be non-negative).

## Testing

### Unit tests (`tests/<package>/`, run via `odin test`)

`tests/cliflag/`
- no args → `Parsed{physical=false, rest=[]}`
- `-L` → physical=false
- `-P` → physical=true
- `-L -P` → physical=true (last wins)
- `-P -L` → physical=false (last wins)
- `--help` → help=true
- `--version` → version=true
- `-X` → `Unknown_Flag`, token = `"-X"`
- `pwd foo` → `foo` returned in `rest` (main is responsible for rejecting it)

`tests/winpath/`
- `get_cwd_physical` returns a non-empty absolute path, backslash-separated, uppercase drive letter
- last character is not `\` unless the path is a drive or share root
- `get_cwd_logical` with `PWD` unset → equals `get_cwd_physical`
- `get_cwd_logical` with `PWD` set to the actual cwd via different casing (e.g. `c:\users\...`) → returns the `PWD` value (identity check matches)
- `get_cwd_logical` with `PWD=C:\bogus\does\not\exist` → falls back to physical
- Hebrew round-trip: create a directory containing `שלום`, set cwd to it, verify UTF-8 output contains the expected byte sequence (`0xD7 0xA9 0xD7 0x9C 0xD7 0x95 0xD7 0x9D`)

`tests/winconsole/`
- Pipe `Writer` (constructed against a temp file handle): `write_string("שלום")` produces exact UTF-8 bytes in the file
- `fmt_last_error(ERROR_FILE_NOT_FOUND)` returns a non-empty message with no trailing CRLF
- (Console branch is not unit-tested — `GetFileType` cannot reliably be faked. Covered by integration tests.)

### Integration tests (`tests/pwd_integration/`, run via `odin test`)

A pure-Odin runner spawns `bin/pwd.exe` via `os.process_exec` (from `core:os`), sets `working_dir` to a temp directory, captures stdout/stderr/exit.

- `bin/pwd.exe` in `<temp>\xyz` → stdout = `<temp>\xyz\r\n`, exit 0
- `bin/pwd.exe -P` in a junction pointing to `<temp>\target` → stdout = `<temp>\target\r\n`, exit 0
- `bin/pwd.exe --help` → stdout contains `Usage:`, exit 0
- `bin/pwd.exe --version` → stdout matches `pwd (winix) ...`, exit 0
- `bin/pwd.exe -X` → stderr contains `unknown option`, exit 2
- `bin/pwd.exe foo` → exit 2
- `bin/pwd.exe` in a Hebrew-named directory, stdout redirected to a file → file bytes are the UTF-8 encoding of that directory name + `\r\n`

Integration tests require `bin/pwd.exe` to exist; the `test.bat` / `test.ps1` scripts build before running them.

## Build

`build.bat`:
```bat
@echo off
if not exist bin mkdir bin
for /d %%D in (cmd\*) do (
    echo Building %%~nxD...
    odin build %%D -out:bin\%%~nxD.exe -o:speed || exit /b 1
)
```

`build.ps1`:
```powershell
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path bin | Out-Null
Get-ChildItem cmd -Directory | ForEach-Object {
    Write-Host "Building $($_.Name)..."
    & odin build $_.FullName "-out:bin\$($_.Name).exe" "-o:speed"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

`test.bat` / `test.ps1`: run `odin test tests/cliflag tests/winpath tests/winconsole`, then invoke the build script, then run `odin test tests/pwd_integration`. Fail fast on any non-zero exit.

`.gitignore`: `bin/`, `*.exe`, `*.pdb`, `*.obj`.

## Out of scope (for this design)

- Additional binaries beyond `pwd`. They will reuse `internal/*` and follow the `cmd/<name>/` pattern, but each gets its own design + plan.
- CI/GitHub Actions configuration.
- Installer/packaging (zip, MSI, scoop, winget).
- Localized error messages (we use system FormatMessageW with neutral language).
- A shared "winix" library API for embedding tool logic into other Odin programs.
