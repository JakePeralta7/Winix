# AGENTS.md

Winix: Windows ports of classic Unix CLI tools in Odin (`windows_amd64`), one standalone `.exe` per tool, no runtime deps. Win32 is reached through `core:sys/windows` (aliased `win`).

## Decision rule: Odin first, Win32 when there is none

- Check `core:os`, `core:strings`, `core:path/filepath` first.
- Drop to Win32 when Odin lacks the feature or its cross-platform layer loses exact Windows semantics: UTF-16 paths, console output, file attributes/share modes, symlink/junction resolution, process enumeration.
- A Win32 call that more than one tool could reuse belongs in `internal/`, not duplicated in `cmd/`.

## Layout and boundaries

- `cmd/<tool>/main.odin` = flags + `main`; implementation is usually `cmd/<tool>/<tool>.odin` (sometimes a thin shim over `internal/`, as in `cmd/pwd`).
- `cmd/*` may import `internal/*` and `core:*`, never another `cmd/*`. `internal/*` may import only `core:*`.
- Shared packages: `internal/cliflag`, `internal/winconsole` (stdout/stderr), `internal/winio` (streaming/I/O), `internal/winpath` (cwd resolution).
- `bin/` is the real build output (git-ignored); `build/` and stray root `*.exe` are stale scratch artifacts.
- README is historically stale (tool list, flags, package names). `cmd/<tool>/main.odin`'s `cliflag.Spec` is authoritative for flags.

## Commands (PowerShell 5.1)

- All: `.\build.ps1` then `.\test.ps1` (unit tests → rebuild → every integration suite). `test.ps1` rebuilds the binaries itself.
- Focused build after editing one tool:
  `odin build cmd\<tool> -out:bin\<tool>.exe -o:size -extra-linker-flags:/OPT:REF,ICF "-define:VERSION=$((Get-Content -Raw VERSION).Trim())"`
  The quotes matter: unquoted `-define:VERSION=(Get-Content ...)` splits into three args. Without these flags the binary is a debug build with no `--version` injection.
- Focused test: `odin test tests\<tool>_integration -define:ODIN_TEST_TRACK_MEMORY=false`; requires `bin\<tool>.exe` already built. Unit packages: `tests/cliflag`, `tests/winconsole`, `tests/pwd_unit`. `test.ps1` sets the memory-tracking flag for every suite because the tests exercise external binaries.
- `pkill_integration` spawns/kills real processes: add `-define:ODIN_TEST_THREADS=1` (`test.ps1` does this).
- No lint/typecheck step; `odin build` is the only compile gate.
- The installed Odin has no `odin fmt`; match the formatting of the file you edit.

## Conventions that differ from defaults

- Locals are `x: Type` (never `var x`); struct literals use `field = value` (not `:`).
- Prefer `for i in 0..<len(x)`; the `for i, v in slice` form mis-types here.
- Don't return a slice compound literal (`[]T{a}`) from a proc — Odin rejects it; `make` + fill.
- `strings.split_iterator` yields immutable parts; use `strings.split` when mutating.
- Qualify enum selectors in `append` (`Column_Kind.PID`, not `.PID`); `goto` is unsupported — use flags + `if`.
- Some Win32 APIs are missing from `core:sys/windows` (`QueryFullProcessImageNameW`, `ProcessIdToSessionId`, `LookupAccountSidW`): declare them in a `foreign import kernel32 "system:Kernel32.lib"` block (see `cmd/pkill`, `cmd/ps`).
- UTF-8 → wide: `win.utf8_to_wstring(s, context.temp_allocator)`; wide → UTF-8: `win.utf16_to_utf8`.
- Check sentinels (`win.INVALID_HANDLE`, `win.INVALID_HANDLE_VALUE`, `winio.INVALID_FILE_ATTRS`), close every handle, prefer `W` APIs, and open files with `FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE`.
- Map `win.GetLastError()` to a typed `Error` enum in `internal/`; don't leak raw DWORDs into `main.odin`.
- Every tool uses `cliflag.Spec`, `VERSION :: #config(VERSION, "dev")`, `--help`/`--version` (exit 0), and `winconsole.stdout()/stderr()`. Booleans: `.Bool_Last_Wins`; values: `.Value_Next` with `values = &[dynamic]string`.
- Exit codes: 0 success, 1 runtime failure, 2 usage error; `pkill` returns 0 if anything matched, else 1.
- Tools that execute a command must stop flag parsing before the command token or the child's flags get eaten (`cmd/env/main.odin` pre-scans args).
- Comments explain *why* a Win32 call is needed, not what it does; doc comments start with the exported name.

## Adding a tool

- Create `cmd/<tool>/` with `main.odin` (+ implementation); `build.ps1` auto-discovers it.
- Add a unit package under `tests/` if needed, an integration package, and register it in `test.ps1`.

## Test and release gotchas

- Integration tests run `bin/<tool>.exe` via `os.process_exec` from the repo root.
- Never use `os.remove_all` in integration tests: its `SHFileOperationW` fallback can raise handled WebDAV path-resolution exceptions that the Odin runner reports as failures. Use `tests/testutil.remove_tree` (`import "../testutil"`).
- Committing a new `VERSION` to `main` triggers the release workflow (build + test, package `bin\winix-<ver>-windows-amd64.zip`, tag `v<ver>`); format must be `X.Y.Z`.
- CI pins Odin `dev-2026-05` with a SHA-256 hash; keep local Odin close — newer nightlies can change APIs/stdlib.
