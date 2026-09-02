# AGENTS.md

Windows ports of classic Unix CLI tools in Odin, calling the Win32 API directly.
One `.exe` per tool, no runtime deps.

## Build & test (Windows, PowerShell 5.1)

- **Build all**: `.\build.ps1` — compiles every `cmd/*` into `bin\<name>.exe`
  with `-define:VERSION` read from the `VERSION` file. Real output dir is `bin\`
  (git-ignored); `build\` and stray root `*.exe` are stale scratch artifacts.
- **Test all**: `.\test.ps1` — unit tests → `build.ps1` → integration tests for
  every tool. Requires binaries to exist; always rebuild before running tests.
- **Focused build** (after editing one tool):
  `odin build cmd\<tool> -out:bin\<tool>.exe`
- **Focused test**: `odin test tests\<tool>_integration`
  (unit packages live under `tests\cliflag`, `tests\winconsole`, `tests\pwd_unit`).
- **Single-threaded tests**: `pkill_integration` spawns/kills real processes and
  MUST run with `-define:ODIN_TEST_THREADS=1` — `test.ps1` handles this.
- There is **no lint/typecheck step**. `odin build` is the only compile gate;
  it rejects the gotchas below.

## Layout & dependency rules

- `cmd/<tool>/main.odin` = flag parsing + `main`; `cmd/<tool>/<tool>.odin` =
  implementation. Tools: cat, df, du, env, grep, head, ls, mv, pkill, ps, pwd,
  rm, sleep, sort, tail, touch, uniq, wc, which.
- `internal/` (shared): `cliflag`, `winconsole`, `winio`, `winpath`. (`internal/regex`
  was removed; grep uses `core:text/regex`, ERE-only.)
- `cmd/*` may import any `internal/*` and `core:*`; `cmd/*` must NOT import other
  `cmd/*`; `internal/*` may only import `core:*`.
- Every tool uses `internal/cliflag` for `-x/--long` flags and `internal/winconsole`
  (`stdout()`/`stderr()` returning `winconsole.Writer`) for output.

**The README was historically stale.** If it starts to drift again (tool list,
`internal/*` package names, per-tool flag tables), trust the code over it —
`cmd/<tool>/main.odin`'s `cliflag.Spec` is authoritative for flag sets.

## Odin / Windows gotchas (compile-time traps)

- Locals are `x: Type`, never `var x: Type` (`var` is a syntax error).
- Struct literals use `field = value`, not `field: value`.
- Prefer `for i in 0..<len(x)`; the two-variable `for i, v in slice` form
  mis-types here (index/value get swapped or become invalid). Verify before relying on it.
- Don't return a slice compound literal (`[]T{a}`) from a proc — Odin rejects it
  (`unsafe to return compound literal of a slice`). Return an index/bool, or `make`+fill.
- `strings.split_iterator` yields immutable parts — you can't reassign in-loop.
  Use `strings.split` into a fresh var when transforming.
- Qualify enum selectors inside `append` (e.g. `Column_Kind.PID`, not `.PID`);
  the bare form often can't infer the type there.
- `goto` is unsupported; use boolean flags/`if`.
- Not every Win32 API is in `core:sys/windows`. Before a `win.<Sync>`, `grep` it
  under `core\sys\windows`. Missing ones (e.g. `QueryFullProcessImageNameW`,
  `ProcessIdToSessionId`, `LookupAccountSidW`) need a `foreign import` block.
  See `cmd\pkill\pkill.odin` / `cmd\ps\ps.odin` for the pattern.
- Strings/UTF-8 → Windows wide strings: use `win.utf8_to_wstring` /
  `win.utf16_to_utf8`.

## CLI/code conventions

- Flags: boolean → `kind = .Bool_Last_Wins, target = &my_bool, value_if_set = true`;
  value flags → `kind = .Value_Next`, collected via `values = &[dynamic]string`.
- Version embedded per tool: `VERSION :: #config(VERSION, "dev")`; build injects it.
- Exit codes: `0` success, `1` runtime failure / process-not-found, `2` usage error
  (cliflag parse failure). pkill: `0` if any matched else `1`.

## Version & release

- `VERSION` is a plain `X.Y.Z` file. `build.ps1` injects it; release CI validates the
  format with `^\d+\.\d+\.\d+$`.
- Committing a new `VERSION` to `main` triggers `.github/workflows/release.yml`
  (build+test, package `bin\winix-<ver>-windows-amd64.zip`, GitHub release `v<ver>`).
- CI pins Odin `dev-2026-05` with a SHA-256-pinned download; local Odin should stay
  close to that build (newer dev builds can change API/standard library).