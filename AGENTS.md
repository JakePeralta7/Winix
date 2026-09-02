# AGENTS.md

Windows ports of classic Unix CLI tools in Odin, calling the Win32 API directly.
One `.exe` per tool, no runtime deps.

This guide is the source of truth for how to add a tool, structure packages, and decide
between Odin's standard library and the Win32 API. Read it before contributing code.

---

## The Decision Rule: Odin first, Win32 when there is none

The single most important rule in this codebase:

> **Use the Odin standard library when it already provides what you need and behaves
> correctly on Windows for this project's use case. Otherwise call the Win32 API directly
> via `core:sys/windows`.**

Apply the rule in this order:

1. Check Odin first. Prefer `core:os` for cross-platform I/O, `core:strings` for string
   handling, and `core:path/filepath` for path manipulation.
2. If Odin lacks the feature, or its cross-platform layer is wrong or lossy for the
   precise Windows semantics we need, use Win32 directly via `core:sys/windows` (aliased
   `win`).
3. When you reach for a Win32 call, prefer to put it in a shared package under
   `internal/` rather than repeating the same `core:sys/windows` code in every `cmd/`.

### Why the fallback exists

Winix intentionally calls Win32 for anything where exact Windows behaviour matters:
UTF-16 path handling, console/terminal output, process enumeration, symlink/junction
resolution, file attributes, and share modes. Odin's `core:os` abstracts these for
portability, but that abstraction can lose the very semantics that make a Unix port feel
correct on Windows. When in doubt about whether Odin's layer is good enough for a specific
call, ask: *does it give us the exact Windows behaviour the tool needs?* If not, use Win32.

### When to use Odin

| Situation | Use | Example in repo |
|-----------|-----|-----------------|
| Cross-platform file/string/path logic with no Windows-specific semantics | `core:strings`, `core:path/filepath`, `core:os` | `cmd/sort`, `cmd/uniq` sorting and comparison |
| Data structures, formatting, hashing, container logic | `core:slice`, `core:fmt`, `core:mem` | general |
| Version constant defined at build time | `#config(VERSION, "dev")` | every `cmd/*/main.odin` |

### When to use Win32 (via `core:sys/windows`)

| Situation | Why Win32 | Shared home in repo |
|-----------|-----------|---------------------|
| Console output (UTF-8 to terminal, proper UTF-16) | `WriteConsoleW` so the terminal gets real UTF-16 with no codepage mangling; `WriteFile` raw bytes when piped/redirected | `internal/winconsole` |
| File streaming that must honour Windows semantics | `CreateFileW` with explicit share modes, `GetFileAttributesW` directory/sentinel checks | `internal/winio` |
| Resolving the real (physical) working directory | `GetCurrentDirectoryW` + `GetFinalPathNameByHandleW` for symlink/junction resolution; honouring `%PWD%` | `internal/winpath` |
| Any UTF-16 `W` API input | Convert with `win.utf8_to_wstring` | per use |
| Process listing / signals / anything `core:os` lacks on Windows | Win32 process APIs | e.g. `cmd/ps`, `cmd/pkill` |

If you add a Win32 call that more than one tool could reasonably reuse, extract it into the
appropriate `internal/` package instead of duplicating it.

---

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

`cmd/<tool>/<tool>.odin` may also act as a thin shim that re-exports shared helpers so
`main.odin` stays small and uniform (see `cmd/pwd/pwd.odin`, which re-exports from
`internal/winpath`).

## Adding a new tool

1. Create `cmd/<tool>/<tool>.odin` with the tool's core logic. Use shared `internal/`
   packages for flags, console output, and I/O. If the logic is Win32-heavy, consider a
   dedicated `internal/` package plus a shim in `cmd/<tool>/<tool>.odin` (pattern: `cmd/pwd`).
2. Create `cmd/<tool>/main.odin`:
   - `VERSION :: #config(VERSION, "dev")`.
   - Declare flags with `cliflag.Spec{...}` and call `cliflag.parse(args, spec)`.
   - Always support `--help` (print `USAGE`, `os.exit(0)`) and `--version`
     (print `"<tool> (winix) " + VERSION`, `os.exit(0)`).
   - Write output through `winconsole.stdout()` / `winconsole.stderr()`.
3. Build with `.\build.ps1` (it auto-discovers `cmd/*`).
4. Add tests: unit tests under `tests/<pkg>_unit/`, an integration test under
   `tests/<tool>_integration/`, and register it in the list in `test.ps1`. Run `.\test.ps1`.

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
- Identifiers: `snake_case` for procedures, variables, and package-level symbols.
- Types: structs and enums use `Title_Case`; error enums end in clear variants
  (e.g. `winio.Error` has `None`, `Not_Found`, `Is_Directory`, `Access_Denied`, ...).
- Alignment & formatting: run `odin fmt` before finishing a file.
- Doc comments: every exported/package-level non-trivial procedure, type, and constant
  gets a short comment beginning with its name, matching existing style.
- No comments unless they earn their place — prefer self-documenting names; use
  comments to explain *why* a Win32 call is required, not what it does.

## Win32 usage guidelines

- Convert UTF-8 strings for `W` APIs with `win.utf8_to_wstring(s, context.temp_allocator)`.
- Map `win.GetLastError()` to a typed `Error` enum in an `internal/` package; don't leak
  raw `DWORD` error codes into `main.odin`.
- Check sentinels explicitly: `win.INVALID_HANDLE_VALUE`, `win.INVALID_HANDLE`,
  `INVALID_FILE_ATTRS` (`winio.INVALID_FILE_ATTRS`) for `GetFileAttributesW`.
- Close every opened handle, usually with `defer win.CloseHandle(h)`.
- Open files with the same generous share mode used elsewhere in the repo:
  `FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE`.
- Prefer the wide (`W`) variants of every API.

## Version & release

- `VERSION` is a plain `X.Y.Z` file. `build.ps1` injects it; release CI validates the
  format with `^\d+\.\d+\.\d+$`.
- Committing a new `VERSION` to `main` triggers `.github/workflows/release.yml`
  (build+test, package `bin\winix-<ver>-windows-amd64.zip`, GitHub release `v<ver>`).
- CI pins Odin `dev-2026-05` with a SHA-256-pinned download; local Odin should stay
  close to that build (newer dev builds can change API/standard library).
