# Winix

Windows ports of classic Unix command-line tools, written in [Odin](https://odin-lang.org/), calling the Windows API directly (`core:sys/windows`). Each tool is a standalone `.exe` with no runtime dependencies.

## Prerequisites

- [Odin compiler](https://odin-lang.org/) on `PATH`
- Windows 10+ (`windows_amd64`)

## Build

```powershell
.\build.ps1
```

All binaries are emitted to `.\bin\`. `build.ps1` compiles every `cmd/*` directory
and injects the version from the `VERSION` file into each binary.

To build a single tool:

```powershell
odin build cmd\ls -out:bin\ls.exe
```

## Test

```powershell
.\test.ps1
```

Runs unit tests for the shared packages (`internal/cliflag`, `internal/winconsole`,
`cmd/pwd`), rebuilds all binaries, then runs integration tests for every tool.
Integration tests execute the built `bin\*.exe`, so always rebuild after editing.

To test a single package:

```powershell
odin test tests\ls_integration
```

## Tools

The 19 tools, each in `cmd/<tool>/`:

cat, df, du, env, grep, head, ls, mv, pkill, ps, pwd, rm, sleep, sort, tail, touch, uniq, wc, which.

### `cat` — concatenate files to stdout

```
cat [-A] [-b] [-e] [-n] [-s] [-T] [-t] [-u] [-v] file ...
```

| Flag | Description |
|------|-------------|
| `-A`, `--show-all` | Equivalent to `-vET` |
| `-b`, `--number-nonblank` | Number non-blank output lines |
| `-e` | Equivalent to `-vE` |
| `-E`, `--show-ends` | Display `$` at end of each line |
| `-n`, `--number` | Number all output lines |
| `-s`, `--squeeze-blank` | Suppress repeated empty output lines |
| `-t` | Equivalent to `-vT` |
| `-T`, `--show-tabs` | Display TAB characters as `^I` |
| `-u` | Ignore buffering (accepted; no-op) |
| `-v`, `--show-nonprinting` | Display non-printing characters |

### `df` — report filesystem usage

```
df [-h] [-i] [-k] [-m] [-P] [-T] [path ...]
```

| Flag | Description |
|------|-------------|
| `-h`, `--human-readable` | Human-readable sizes (powers of 1024) |
| `-i`, `--inodes` | Show inode counts (derived from bytes/4096 on Windows) |
| `-k` | 1 KiB blocks |
| `-m` | 1 MiB blocks |
| `-P`, `--portability` | POSIX output format |
| `-T`, `--print-type` | Print the filesystem type (e.g. NTFS) |

### `du` — estimate file space usage

```
du [-a] [-c] [-d N] [-h] [-k] [-m] [-s] [path ...]
```

| Flag | Description |
|------|-------------|
| `-a`, `--all` | Print sizes for individual files too |
| `-c`, `--total` | Print a grand total |
| `-d`, `--max-depth=N` | Limit directory printing to depth N |
| `-h`, `--human-readable` | Human-readable sizes |
| `-k` | 1 KiB blocks |
| `-m` | 1 MiB blocks |
| `-s`, `--summarize` | Print only a per-argument total |

### `env` — run a program in a modified environment

```
env [-i] [-u NAME] [-0] [NAME=VALUE ...] [COMMAND [ARG ...]]
```

| Flag | Description |
|------|-------------|
| `-i`, `--ignore-environment` | Start with an empty environment |
| `-u`, `--unset=NAME` | Remove a variable from the environment |
| `-0`, `--null` | Separate output with NUL instead of newline |

### `grep` — search for text patterns

```
grep [OPTIONS] PATTERN [FILE ...]
grep [OPTIONS] -e PATTERN [-e PATTERN ...] [FILE ...]
```

| Flag | Description |
|------|-------------|
| `-E`, `--extended-regexp` | PATTERN is an ERE (default) |
| `-F`, `--fixed-strings` | PATTERN is a literal string |
| `-i`, `--ignore-case` | Ignore case |
| `-n`, `--line-number` | Print line numbers |
| `-l`, `--files-with-matches` | Print only matching file names |
| `-L`, `--files-without-match` | Print only non-matching file names |
| `-v`, `--invert-match` | Select non-matching lines |
| `-c`, `--count` | Print a match count per file |
| `-q`, `--quiet` | Suppress output; exit based on match only |
| `-s`, `--no-messages` | Suppress file error messages |
| `-r`, `--recursive` | Search directories recursively |
| `-e`, `--regexp=PATTERN` | Specify a pattern |
| `-f`, `--file=FILE` | Read patterns from FILE |

Patterns are handled by Odin's `core:text/regex` (ERE only).

### `head` — print the first part of files

```
head [-n N] [-c N] [-q] [-v] [-z] [file ...]
```

| Flag | Description |
|------|-------------|
| `-n`, `--lines=N` | Print the first N lines |
| `-c`, `--bytes=N` | Print the first N bytes |
| `-q`, `--quiet` | Never print file headers |
| `-v`, `--verbose` | Always print file headers |
| `-z`, `--zero-terminated` | NULL line terminator |

### `ls` — list directory contents

```
ls [-a] [-l] [-h] [-1] [-r] [-R] [-S] [-t] [--color[=WHEN]] [path ...]
```

| Flag | Description |
|------|-------------|
| `-a`, `--all` | Include hidden files and `.` / `..` |
| `-l` | Long listing format |
| `-h`, `--human-readable` | Human-readable sizes |
| `-r`, `--reverse` | Reverse sort order |
| `-R`, `--recursive` | List subdirectories recursively |
| `-S` | Sort by size, decreasing |
| `-t` | Sort by modification time, newest first |
| `-1` | One entry per line |
| `--color[=WHEN]` | `auto`, `always`, or `never` (directories in blue) |

Multiple paths are accepted; each is printed with a `path:` header when more than
one is given. Exits 1 if any path cannot be accessed.

### `mv` — move / rename files

```
mv [-f] [-i] [-n] [-u] [-v] [-T] [-t DIR] source ... [dest]
```

| Flag | Description |
|------|-------------|
| `-f`, `--force` | Overwrite without prompting (overrides `-i`) |
| `-i`, `--interactive` | Prompt before overwrite |
| `-n`, `--no-clobber` | Do not overwrite an existing file |
| `-u`, `--update` | Move only when source is newer |
| `-v`, `--verbose` | Print each moved path |
| `-t`, `--target-directory=DIR` | Move all sources into DIR |
| `-T`, `--no-target-directory` | Treat dest as a normal file |

### `pkill` — kill processes by name pattern

```
pkill [-d] [-e] [-f] [-n] [-o] [-v] [-x] [-P PID] [-s N] [--help] [--version] PATTERN ...
```

| Flag | Description |
|------|-------------|
| `-d`, `--dry-run` | Show what would be killed without killing |
| `-e`, `--echo` | List what is being killed |
| `-f`, `--full` | Match against the full image path |
| `-n`, `--newest` | Match only the newest started process |
| `-o`, `--oldest` | Match only the oldest started process |
| `-v`, `--inverse` | Match processes that do NOT match |
| `-x`, `--exact` | Require an exact (full name) match |
| `-P`, `--parent=PID` | Match only processes with one of these parents |
| `-s`, `--session=N` | Match only processes in one of these session IDs |
| `-u`, `--uid` | Accepted (parsed; no-op on Windows) |
| `-t`, `--terminal` | Accepted (parsed; no-op on Windows) |

Exits 0 if at least one process matched, 1 if none were found, 2 on usage error.

### `ps` — report a snapshot of current processes

```
ps [-e] [-f] [-o FORMAT] [-p PID] [-u USER] [-t SESSION]
```

| Flag | Description |
|------|-------------|
| `-e`, `--everyone` | List all processes (default) |
| `-f`, `--full` | Full format (adds SESS and USER columns) |
| `-o`, `--format=FORMAT` | Comma-separated columns: `pid, ppid, name, session, user` |
| `-p`, `--pid=PID` | Select processes by PID |
| `-u`, `--user=USER` | Select processes owned by USER |
| `-t`, `--tty=SESSION` | Select processes in a terminal session |

### `pwd` — print working directory

```
pwd [-L | -P] [--help] [--version]
```

| Flag | Description |
|------|-------------|
| `-L` | Logical path (default) |
| `-P` | Physical path (resolves symlinks/junctions) |

`-L` and `-P` may both appear; the **last one wins**. Output is a Windows-native
path (backslash separators, uppercase drive letter). Exits 1 on a runtime error,
2 on a usage error.

### `rm` — remove files or directories

```
rm [-d] [-f] [-i] [-I] [-r] [-R] [-v] file ...
```

| Flag | Description |
|------|-------------|
| `-d`, `--dir` | Remove empty directories |
| `-f`, `--force` | Ignore non-existent files; never prompt |
| `-i`, `--interactive` | Prompt before every removal |
| `-I` | Prompt once (recursive or >3 files) |
| `-r`, `-R`, `--recursive` | Remove directories and contents recursively |
| `-v`, `--verbose` | Print each removed path |

### `sleep` — delay for a given time

```
sleep DURATION ...
```

`DURATION` supports `s`/`m`/`h`/`d` suffixes. Multiple durations are summed.

### `sort` — sort lines of text files

```
sort [-b] [-f] [-g] [-n] [-r] [-u] [-V] [-c | -C] [-z] [-o FILE] [file ...]
```

| Flag | Description |
|------|-------------|
| `-r`, `--reverse` | Reverse the result of comparisons |
| `-u`, `--unique` | Output only the first of an equal run |
| `-n`, `--numeric-sort` | Compare by numeric value |
| `-f`, `--ignore-case` | Fold case |
| `-b`, `--ignore-leading-blanks` | Ignore leading blanks |
| `-g`, `--general-numeric-sort` | General numeric sort |
| `-V`, `--version-sort` | Natural version sort |
| `-c`, `--check` | Check sorted-ness, report the first disorder |
| `-C`, `--check-silent` | Check sorted-ness silently |
| `-z`, `--zero-terminated` | NULL line terminator |
| `-o`, `--output=FILE` | Write result to FILE |

### `tail` — print the last part of files

```
tail [-n N] [-c N] [-f] [-q] [-v] [-z] [-s SEC] [retry] [file ...]
```

| Flag | Description |
|------|-------------|
| `-n`, `--lines=N` | Print the last N lines |
| `-c`, `--bytes=N` | Print the last N bytes |
| `-f`, `--follow` | Output appended data as the file grows |
| `-q`, `--quiet` | Never print file headers |
| `-v`, `--verbose` | Always print file headers |
| `-z`, `--zero-terminated` | NULL line terminator |
| `-s`, `--sleep-interval=SEC` | With `-f`, sleep SEC between checks |
| `--retry` | Keep trying to open a file |

### `touch` — update file timestamps

```
touch [-a] [-c] [-m] [-r FILE] file ...
```

| Flag | Description |
|------|-------------|
| `-a`, `--access-time` | Change only the access time |
| `-c`, `--no-create` | Do not create files |
| `-m`, `--modification-time` | Change only the modification time |
| `-r`, `--reference=FILE` | Use FILE's times instead of the current time |

### `uniq` — filter adjacent matching lines

```
uniq [-c] [-d] [-u] [-i] [-f N] [-s N] [-w N] [-z] [file]
```

| Flag | Description |
|------|-------------|
| `-c`, `--count` | Prefix lines by the number of occurrences |
| `-d`, `--repeated` | Only print lines that appear more than once per group |
| `-u`, `--unique` | Only print lines that appear exactly once |
| `-i`, `--ignore-case` | Ignore case |
| `-f`, `--skip-fields=N` | Skip the first N fields |
| `-s`, `--skip-chars=N` | Skip the first N characters |
| `-w`, `--check-chars=N` | Compare only the first N characters |
| `-z`, `--zero-terminated` | NULL line terminator |

Only adjacent duplicate lines are collapsed; pipe through `sort` for global
deduplication. Accepts at most one file operand; with no file reads from stdin.

### `wc` — print newline, word, and byte counts

```
wc [-l] [-w] [-c] [-m] [-L] [file ...]
```

| Flag | Description |
|------|-------------|
| `-l`, `--lines` | Print newline counts |
| `-w`, `--words` | Print word counts |
| `-c`, `--bytes` | Print byte counts |
| `-m`, `--chars` | Print character counts |
| `-L`, `--max-line-length` | Print the longest line length |

### `which` — locate a command on PATH

```
which [-a] [-s] name ...
```

| Flag | Description |
|------|-------------|
| `-a`, `--all` | Print all matching paths, not just the first |
| `-s`, `--silent`, `--no-output` | No output; only set the exit status |

Searches the directories in `%PATH%` (and the App Paths registry keys), appending
`.exe`, `.cmd`, `.bat`, and `.com` when no extension is given. Exits 1 if any name
is not found.

## Repository layout

```
Winix/
├── cmd/<tool>/            # 19 binaries, one directory each
│   ├── main.odin          #   flag parsing + main
│   └── <tool>.odin        #   implementation
├── internal/              # Shared packages
│   ├── cliflag/           #   Modular -x/--long flag parser
│   ├── winconsole/        #   WriteConsoleW / UTF-8 stdout+stderr, prompting
│   ├── winio/             #   Path/Win32 file helpers
│   └── winpath/           #   cwd resolution (logical + physical)
├── tests/                 # Unit and integration tests
│   ├── cliflag/           #   unit
│   ├── winconsole/        #   unit
│   ├── pwd_unit/          #   unit
│   └── <tool>_integration/
├── bin/                   # Build output (git-ignored)
├── build.bat / build.ps1
├── test.bat / test.ps1
├── VERSION                # X.Y.Z, injected into each binary at build
├── LICENSE
└── README.md
```

**Dependency rules:**
- `cmd/<name>` may import any `internal/*` package and `core:*`.
- `cmd/*` packages must not import other `cmd/*` packages.
- `internal/*` packages may only import `core:*`.

## Versioning

`VERSION` is a plain `X.Y.Z` file. Committing a version change on `main` triggers
the release workflow, which validates the format, builds and tests, packages
`bin\winix-<ver>-windows-amd64.zip`, and creates a GitHub release `v<ver>`.

## License

See [LICENSE](LICENSE).