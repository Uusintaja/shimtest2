# ConPTY Wrapper - 0.2.0-rc2-dev

A Windows PowerShell 5.1 wrapper for line-oriented Windows console programs using ConPTY.

This working tree is post-rc hardening after the frozen `0.2.0-rc1` baseline. The rc1 sign-off remains documented under `docs\release\FINAL_SIGNOFF_0.2.0-rc1.md`.

Primary implementation:

```text
wrapper-csharphost.ps1
```

Reference/fallback implementation:

```text
legacy\wrapper.ps1
```

---

## What this wrapper does

- Starts a console application inside ConPTY.
- Bridges app terminal output to the host console.
- Forwards basic line input.
- Converts host Ctrl+C into ConPTY ETX `0x03`.
- Handles app exit, timeout, and kill policies.
- Injects arguments, working directory, and environment variables.
- Supports normal-path PostActions.
- Handles console close/logoff/shutdown as best-effort safety paths.
- Writes wrapper lifecycle logs, RunId, timing, and optional JSON result.

---

## What this wrapper does not guarantee

- Full TUI support.
- Raw keyboard/IME/complex Unicode correctness.
- Strict stdout/stderr separation in ConPTY mode.
- Business-grade app output logs.
- Guaranteed cleanup during OS close/logoff/shutdown; those paths are best-effort.

---

## Requirements

- Windows 10 1809+; tested mainly on Windows 10/11 class systems.
- Windows PowerShell 5.1.
- .NET Framework with `Add-Type` support.
- Execution policy allowing the script to run.

Example:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

---

## Quick start

Ensure test programs are compiled first; see [Compile test programs](#compile-test-programs).

```powershell
cd .\shimtest2

.\wrapper-csharphost.ps1 `
  -ConfigPath .\configs\sample.stdown.ps1 `
  -JsonOutputPath .\logs\result.csharphost.stdown.json
```

Press Ctrl+C after several counter lines. Expected result:

- app receives Ctrl+C;
- app exits cleanly;
- `work\stdown\output\output.txt` contains `done`;
- PostActions pass.

---

## Debug-friendly options

```powershell
-Json
-JsonOutputPath .\logs\result.json
-PauseOnExit
-NoSummary
```

Recommended during manual debugging:

```powershell
.\wrapper-csharphost.ps1 `
  -ConfigPath .\configs\sample.stdown.ps1 `
  -JsonOutputPath .\logs\result.csharphost.stdown.json `
  -PauseOnExit
```

---

## Compile test programs

See:

```text
docs\reference\TEST_PROGRAMS.md
```

Example with MinGW-w64:

```powershell
x86_64-w64-mingw32-gcc .\tests\args_env.c -o .\bin\args_env.exe
```

---

## Run non-interactive test matrix

```powershell
.\scripts\run-tests.ps1 -Implementation CSharpHost
```

Run both implementations:

```powershell
.\scripts\run-tests.ps1 -Implementation Both
```

Run interactive tests:

```powershell
.\scripts\run-tests.ps1 -Implementation CSharpHost -IncludeInteractive
```

Run boundary lifecycle tests:

```powershell
.\scripts\test-boundary-runs.ps1
```

Run unsupported same-process concurrency negative test:

```powershell
.\scripts\test-unsupported-concurrent-run.ps1
```

---

## Minimal production-like deployment

For wrapping your own `myapp.exe`, the minimal recommended file set is:

```text
wrapper-csharphost.ps1
src\common.ps1
configs\myapp.ps1
bin\myapp.exe
```

Recommended supporting files:

```text
docs\reference\CONFIG_REFERENCE.md
README.md
logs\                         # created automatically if configured
work\                         # created automatically if configured
```

Use `wrapper-csharphost.ps1` as the mainline. Keep `legacy\wrapper.ps1` only as a reference/fallback.

---

## Important docs

```text
docs\reference\CONFIG_REFERENCE.md
docs\history\design_v2.md
docs\release\comparison_report.md
docs\architecture\architecture_0.2.0-rc1.md
docs\architecture\review.md
docs\release\release_candidate_stabilization.md
docs\release\RELEASE_CHECKLIST.md
docs\release\FINAL_SIGNOFF_0.2.0-rc1.md
docs\release\ADVISORY_NOTES.md
assistant\DOCUMENTATION_POLICY.md
CODING_GUIDELINES.md
scripts\validate-release.ps1
docs\review_agents\DOC_REVIEW_AGENT.md
USER.md
WORKFLOW_RULES.md
docs\review_agents\CODE_REVIEW_AGENT.md
ROADMAP.md
```

---

## Recommended mainline

Use `wrapper-csharphost.ps1` for serious testing and production-like scenarios.

`legacy\wrapper.ps1` is retained as a PowerShell-main reference/fallback and does not implement all close/shutdown behavior.
