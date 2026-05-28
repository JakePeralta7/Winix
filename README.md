# Winix

Windows ports of classic Unix command-line tools, written in [Odin](https://odin-lang.org/), calling the Windows API directly (`core:sys/windows`). Each tool is a standalone `.exe` with no runtime dependencies.

## Prerequisites

- [Odin compiler](https://odin-lang.org/) on `PATH`
- Windows 10+ (`windows_amd64`)

## Build

```cmd
build.bat
```

or

```powershell
.\build.ps1
```

All binaries are emitted to `.\bin\`.

## Test

```cmd
test.bat
```

or

```powershell
.\test.ps1
```

Runs unit tests for internal packages, rebuilds all binaries, then runs integration tests for every tool.

## Tools

### `ls` — list directory contents

```
ls [-l] [-a] [-1] [--help] [--version] [path ...]
```

| Flag | Description |
|------|-------------|
| `-l`, `--long` | Long listing format (permissions, size, date) |
| `-a`, `--all` | Include hidden files and `.` / `..` |
| `-1` | One entry per line |
| `--help` | Print usage and exit 0 |
| `--version` | Print version and exit 0 |

Multiple paths are accepted; each is printed with a `path:` header when more than one is given. Exits 1 if any path cannot be accessed.

---

### `pwd` — print working directory

```
pwd [-L | -P] [--help] [--version]
```

| Flag | Description |
|------|-------------|
| `-L` | Logical: honour `%PWD%` when it refers to the actual cwd (default) |
| `-P` | Physical: resolve symlinks and junctions via `GetFinalPathNameByHandleW` |
| `--help` | Print usage and exit 0 |
| `--version` | Print version and exit 0 |

`-L` and `-P` may both appear; the **last one wins**. Output is a Windows-native path (backslash separators, uppercase drive letter). Exits 1 on a runtime error, 2 on a usage error.

---

### `rm` — remove files or directories

```
rm [-r] [-f] [-v] [--help] [--version] file ...
```

| Flag | Description |
|------|-------------|
| `-r`, `-R`, `--recursive` | Remove directories and their contents recursively |
| `-f`, `--force` | Ignore non-existent files; never prompt |
| `-v`, `--verbose` | Print each removed path |
| `--help` | Print usage and exit 0 |
| `--version` | Print version and exit 0 |

At least one path operand is required. Exits 1 if any removal fails, 2 on a usage error.

---

### `cat` — concatenate files to stdout

```
cat [--help] [--version] file ...
```

| Flag | Description |
|------|-------------|
| `--help` | Print usage and exit 0 |
| `--version` | Print version and exit 0 |

Prints file contents to standard output in operand order. Exits 1 if any file cannot be read, 2 on a usage error.

---

### `which` — locate a command on PATH

```
which [-a] [--help] [--version] name ...
```

| Flag | Description |
|------|-------------|
| `-a`, `--all` | Print all matching paths, not just the first |
| `--help` | Print usage and exit 0 |
| `--version` | Print version and exit 0 |

Searches the directories in `%PATH%` for each name, appending `.exe`, `.cmd`, `.bat`, and `.com` when no extension is given. Exits 1 if any name is not found.

---

### `pkill` — kill processes by name pattern

```
pkill [-x] [-n] [-v] [--help] [--version] pattern ...
```

| Flag | Description |
|------|-------------|
| `-x`, `--exact` | Pattern must match the full process name (e.g. `notepad.exe`) |
| `-n`, `--dry-run` | Show what would be killed without actually killing |
| `-v`, `--verbose` | Print each killed process |
| `--help` | Print usage and exit 0 |
| `--version` | Print version and exit 0 |

`--dry-run` implies `--verbose`. All process termination on Windows is unconditional (no POSIX signal support). Exits 0 if at least one process matched, 1 if none were found, 2 on an enumeration error.

---

### `sort` — sort lines of text files

```
sort [-r] [-u] [-n] [-f] [--help] [--version] [file ...]
```

| Flag | Description |
|------|-------------|
| `-r`, `--reverse` | Reverse the result of comparisons |
| `-u`, `--unique` | Output only the first of an equal run |
| `-n`, `--numeric-sort` | Compare according to string numerical value |
| `-f`, `--ignore-case` | Fold lower case to upper case characters |
| `--help` | Print usage and exit 0 |
| `--version` | Print version and exit 0 |

Multiple files are concatenated before sorting. With no files reads from stdin. Exits 1 if any file cannot be read, 2 on a usage error.

---

### `uniq` — filter adjacent matching lines

```
uniq [-c] [-d] [-u] [-i] [--help] [--version] [file]
```

| Flag | Description |
|------|-------------|
| `-c`, `--count` | Prefix lines by the number of occurrences |
| `-d`, `--repeated` | Only print lines that appear more than once per group |
| `-u`, `--unique` | Only print lines that appear exactly once |
| `-i`, `--ignore-case` | Ignore differences in case when comparing |
| `--help` | Print usage and exit 0 |
| `--version` | Print version and exit 0 |

Only adjacent duplicate lines are collapsed; pipe through `sort` first for global deduplication. Accepts at most one file operand. With no file reads from stdin. Exits 1 if the file cannot be read, 2 on a usage error.

---

## Repository layout

```
Winix/
├── cmd/                     # One sub-directory per binary
│   ├── ls/main.odin
│   ├── pkill/main.odin
│   ├── pwd/main.odin
│   ├── rm/main.odin
│   ├── cat/main.odin
│   └── which/main.odin
├── internal/                # Shared packages (no cross-internal deps)
│   ├── cliflag/             # Minimal flag parser
│   ├── wincat/              # File-to-stdout streaming
│   ├── winconsole/          # WriteConsoleW / UTF-8 stdout+stderr
│   ├── winls/               # Directory listing logic
│   ├── winpath/             # cwd resolution (logical + physical)
│   ├── winpkill/            # Process enumeration and termination
│   ├── winrm/               # File / directory removal
│   └── winwhich/            # PATH search
├── tests/                   # Unit and integration tests
│   ├── cliflag/
│   ├── winconsole/
│   ├── winpath/
│   ├── ls_integration/
│   ├── pkill_integration/
│   ├── pwd_integration/
│   ├── rm_integration/
│   ├── cat_integration/
│   └── which_integration/
├── bin/                     # Build output (git-ignored)
├── build.bat
├── build.ps1
├── test.bat
├── test.ps1
├── LICENSE
└── README.md
```

**Dependency rules:**
- `cmd/<name>` may import any `internal/*` package and `core:*`.
- `cmd/*` packages must not import other `cmd/*` packages.
- `internal/*` packages may only import `core:*`.

## License

See [LICENSE](LICENSE).
