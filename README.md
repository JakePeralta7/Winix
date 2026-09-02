# Winix

Windows ports of classic Unix command-line tools, written in [Odin](https://odin-lang.org/), calling the Windows API directly (`core:sys/windows`). Each tool is a standalone `.exe` with no runtime dependencies.

## Prerequisites

- [Odin compiler](https://odin-lang.org/) on `PATH`
- Windows 10+ (`windows_amd64`)

## Build & Test

```powershell
.\build.ps1    # builds every tool in cmd/ into .\bin\
.\test.ps1     # unit tests, rebuild, then integration tests for every tool
```

`build.bat` and `test.bat` provide the equivalent batch entry points.

## Tools

Every tool supports `--help` and `--version` (both exit 0). Use `[--help] [--version]` shorthand.

| Tool | Usage | Description |
|------|-------|-------------|
| `cat` | `cat file ...` | Concatenate files to stdout |
| `df` | `df [-h] [path ...]` | Report filesystem disk space usage |
| `du` | `du [-s] [-a] [-h] [path ...]` | Estimate file space usage |
| `env` | `env [-u NAME]` | Print the environment, optionally excluding names |
| `grep` | `grep [-i] [-n] [-l] [-v] [-c] [-r] PATTERN [file ...]` | Search for patterns in files |
| `head` | `head [-n COUNT] file ...` | Print the first lines of files |
| `ls` | `ls [-l] [-a] [-1] [path ...]` | List directory contents |
| `mv` | `mv [-f] [-n] [-v] source dest` | Move or rename files |
| `pkill` | `pkill [-x] [-n] [-v] pattern ...` | Kill processes by name pattern |
| `ps` | `ps` | Report active processes |
| `pwd` | `pwd [-L \| -P]` | Print the working directory |
| `rm` | `rm [-r] [-f] [-v] file ...` | Remove files or directories |
| `sleep` | `sleep DURATION [DURATION ...]` | Delay for a specified amount of time |
| `sort` | `sort [-r] [-u] [-n] [-f] [file ...]` | Sort lines of text files |
| `tail` | `tail [-n COUNT] file ...` | Print the last lines of files |
| `touch` | `touch file ...` | Update file timestamps or create empty files |
| `uniq` | `uniq [-c] [-d] [-u] [-i] [file]` | Filter adjacent duplicate lines |
| `wc` | `wc [-l] [-w] [-c] [file ...]` | Count lines, words, and characters |
| `which` | `which [-a] name ...` | Locate a command on `%PATH%` |

Run any tool with `--help` for the full flag reference and exit-code details.

## Repository layout

```
cmd/<name>/     One directory per binary (implementation + main.odin)
internal/       Shared packages: cliflag, winconsole, winio, winpath
tests/          Unit tests (internal) and integration tests per tool
bin/            Build output (git-ignored)
build.ps1       Build all tools
test.ps1        Run unit then integration tests
```

**Dependency rules:** `cmd/<name>` may import any `internal/*` and `core:*` package, but never
another `cmd/*`. `internal/*` packages may only import `core:*`.

## License

See [LICENSE](LICENSE).