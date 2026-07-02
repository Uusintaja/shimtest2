# Release Checklist - ConPTY Wrapper 0.2.0-rc1

Version: 0.2.0-rc1  
Primary implementation: `wrapper-csharphost.ps1`  
Status: Release-candidate checklist

---

## 1. Required files for deployment

Minimum CSharpHost deployment:

```text
wrapper-csharphost.ps1
src\common.ps1
configs\<app>.ps1
bin\<app>.exe
```

Recommended support files:

```text
README.md
docs\reference\CONFIG_REFERENCE.md
docs\release\release_candidate_stabilization.md
logs\                 # created by config if included in CreateDirectories
work\                 # created by config if included in CreateDirectories
```

Reference/fallback only:

```text
legacy\wrapper.ps1
```

Do not treat `legacy\wrapper.ps1` as the main release line. It does not have full Close/Shutdown parity.

---

## 2. Pre-run checks

Before running a wrapped app:

- [ ] Windows PowerShell 5.1 is available.
- [ ] Execution policy allows script execution for the current process.
- [ ] App executable path exists.
- [ ] App dependency files/DLLs/config folders are present.
- [ ] Config file exists under `configs\`.
- [ ] `CreateDirectories` includes required log/work/data directories.
- [ ] `WorkingDirectory` matches the app's expected runtime directory.
- [ ] `EnvironmentVariables` includes required runtime env overrides.
- [ ] Sensitive env values are not logged unless explicitly intended.

Recommended one-session setup:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

---

## 3. Standard validation commands

### 3.0 Automated release validation

```powershell
.\scripts\validate-release.ps1 `
  -ExpectedVersion "0.2.0-rc1" `
  -RunNonInteractiveTests `
  -GenerateMarkdownReport
```

Expected:

- [ ] OverallPass is True.
- [ ] JSON report is generated under `logs\`.
- [ ] Markdown sign-off report is generated under `logs\`.
- [ ] Any warning is reviewed manually.


### 3.1 Basic CSharpHost validation

Press Ctrl+C after several counter lines.

```powershell
.\wrapper-csharphost.ps1 `
  -ConfigPath .\configs\sample.stdown.ps1 `
  -JsonOutputPath .\logs\result.csharphost.stdown.json
```

Expected:

- [ ] Ctrl+C exits app cleanly.
- [ ] `PostActions` pass.
- [ ] JSON result contains `WrapperVersion = 0.2.0-rc1`.
- [ ] Wrapper log contains `RunId`.

### 3.2 Non-interactive matrix

```powershell
.\scripts\run-tests.ps1 -Implementation CSharpHost
```

Expected:

- [ ] All non-interactive tests PASS.

### 3.3 Boundary lifecycle tests

```powershell
.\scripts\test-boundary-runs.ps1
```

Expected:

- [ ] Sequential same-PowerShell invocations PASS.
- [ ] Parallel independent powershell.exe invocations PASS.

Unsupported same-process concurrency negative test:

```powershell
.\scripts\test-unsupported-concurrent-run.ps1
```

Expected:

- [ ] First run completes successfully.
- [ ] Second concurrent same-process run is rejected with a clear structured error.

### 3.4 Ctrl+C Continue policy manual test

```powershell
.\wrapper-csharphost.ps1 `
  -ConfigPath .\configs\sample.ctrlc_counter.ps1 `
  -JsonOutputPath .\logs\result.ctrlc_counter.json
```

Expected:

- [ ] Press Ctrl+C three times with short pauses.
- [ ] App exits on third Ctrl+C.
- [ ] `CtrlCSentCount >= 3`.
- [ ] `CtrlCUnresponsiveCount >= 2`.

### 3.5 Interactive matrix

```powershell
.\scripts\run-tests.ps1 -Implementation CSharpHost -IncludeInteractive
```

Expected:

- [ ] `stdown` Ctrl+C PASS.
- [ ] `ignore_ctrlc` timeout/kill PASS.
- [ ] `echo` basic line input PASS.
- [ ] `bulk_output_ctrlc` expected default Ctrl+C exit PASS.

---

## 4. Manual signal tests

### 4.1 Ctrl+C

- [ ] Start wrapped app.
- [ ] Press Ctrl+C.
- [ ] App receives Ctrl+C semantics.
- [ ] App exits within `CtrlCGracePeriodMs` when CtrlCUnresponsivePolicy=Kill.
- [ ] Result is written.
- [ ] Normal-path `PostActions` run.

Important logs:

```text
CTRL_C_EVENT captured
CtrlC path sent ETX 0x03
Signal response timing
Normal exit output drain completed
Wrapper CSharpHost core ended
Wrapper PowerShell post-actions ended
```

### 4.2 Ctrl+Break

Optional emergency path test.

- [ ] Press Ctrl+Break.
- [ ] Wrapper aborts/terminates app.
- [ ] Behavior is recorded as emergency path.

### 4.3 Console Close

Open a dedicated console window, run wrapper, then click the window close button.

Expected:

- [ ] Wrapper log contains `CTRL_CLOSE_EVENT captured`.
- [ ] Wrapper sends ETX `0x03`.
- [ ] App exits or is killed within close budget.
- [ ] No app process remains.
- [ ] Do not require JSON result.
- [ ] Do not require PostActions.

Important:

```text
Close PostActions are skipped by default (`CloseSkipPostActions=$true`). If set to `$false` and the process resumes after the best-effort handler, PostActions may run, but this is not guaranteed because the process may terminate before returning to PowerShell.
```

### 4.4 Logoff / Shutdown / Restart

Use a VM or safe test environment.

Commands:

```cmd
shutdown /l
shutdown /r /t 0
```

Expected:

- [ ] Wrapper log contains `CTRL_LOGOFF_EVENT` or `CTRL_SHUTDOWN_EVENT`.
- [ ] App receives Ctrl+C semantics.
- [ ] App exits or is killed within shutdown budget.
- [ ] App data remains valid.
- [ ] Do not require JSON result.
- [ ] Do not require PostActions.

Important logs:

```text
ShutdownWindowRouter registered. EnableShutdownSentinel=True
SetProcessShutdownParameters ... verified=True
CTRL_LOGOFF_EVENT captured
CTRL_SHUTDOWN_EVENT captured
```

---

## 5. Log checks

For each run, wrapper log should include:

- [ ] `RunId`.
- [ ] `Wrapper PowerShell entry started`.
- [ ] `AppArgsRawCount` / `AppArgsRaw`.
- [ ] `EnvironmentOverridesCount`.
- [ ] `Wrapper CSharpHost core started`.
- [ ] `AppPath`.
- [ ] `AppArgsLine`.
- [ ] `Started app. PID=...`.
- [ ] `SetProcessShutdownParameters ... verified=True` when shutdown sentinel is enabled.
- [ ] `Normal exit ConPTY close-for-output-completion called` on normal exit paths.
- [ ] Event-specific timing logs.
- [ ] Core end marker or best-effort completion marker.

Normal path should also include:

- [ ] `PostActions timing`.
- [ ] `Wrapper PowerShell post-actions ended`.

Best-effort paths may include:

- [ ] `Wrapper PowerShell post-actions skipped`, if PowerShell regains control.

But it is acceptable if best-effort paths end before PowerShell post-action layer runs.

---

## 6. Configuration sanity checklist

For a new app config:

- [ ] `AppPath` is correct.
- [ ] `AppArgs` uses array form, not a single manually quoted command line.
- [ ] `WorkingDirectory` is intentional.
- [ ] `EnvironmentVariables` includes only required overrides.
- [ ] `InheritParentEnvironment = $true` unless isolation is required.
- [ ] `LogEnvironmentVariableValues = $false` unless debugging safe values.
- [ ] `InputMode = "None"` for non-interactive service-style apps.
- [ ] `InputMode = "Line"` only for basic line-oriented interactive apps.
- [ ] `CtrlCGracePeriodMs` reflects observed app graceful-exit time when set explicitly.
- [ ] Close/Shutdown budgets are independent from Ctrl+C timeout.
- [ ] Shutdown priority verification logs `actualLevel=0x3FF` and `verified=True`.
- [ ] `NormalExitOutputDrainMilliseconds` reflects app's observed output tail time.
- [ ] `NormalExitClosePseudoConsoleBeforeDrain` remains `$true` unless deliberately testing alternate drain behavior.
- [ ] `CloseSkipPostActions` and `ShutdownSkipPostActions` are understood as best-effort gates, not guarantees.

---

## 7. Known limitations to acknowledge

Before rc1 sign-off, acknowledge:

- [ ] Close/logoff/shutdown are best-effort.
- [ ] PowerShell post-actions are not guaranteed in Close/Shutdown.
- [ ] `AppOutputLogFilePath` is auxiliary, not business-grade logging.
- [ ] ConPTY combines stdout/stderr into a terminal stream.
- [ ] Complex TUI is out of scope.
- [ ] Unicode/IME/raw input is not guaranteed.
- [ ] `InputMode=Char` is reserved/experimental.
- [ ] `ShutdownMode=CancelAndReissue` is reserved and not implemented.
- [ ] `ContentMatcher` is reserved and not implemented.

---

## 8. RC1 freeze criteria

RC1 can be considered frozen when:

- [ ] CSharpHost non-interactive matrix PASS.
- [ ] CSharpHost interactive matrix PASS.
- [ ] `stdown` close/logoff/shutdown PASS in VM.
- [ ] `ignore_ctrlc` close/logoff timeout-kill PASS.
- [ ] One production-like app config validates successfully.
- [ ] Documentation is consistent with current behavior.
- [ ] No new feature work is mixed into the release-candidate branch.

---

## 9. Post-RC priorities

Recommended order after RC stabilization:

1. Output pump state-machine refactor, if maintainability becomes an issue.
2. Optional precompiled C# host packaging.
3. Unicode/raw input module design.
4. Content matcher / auto-response module.
5. Optional stdout/stderr separated non-ConPTY mode.
