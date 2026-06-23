# Architecture Review and Cleanup Plan

Date: 2026-06-18  
Baseline version: 0.2.0-rc1  
Scope: Step 8.2 - architecture review before adding new features

---

## 1. Executive summary

The wrapper has reached a stable functional baseline for the CSharpHost mainline:

- Ctrl+C forwarding works.
- Console close best-effort works.
- Logoff/shutdown/restart best-effort works via hidden window `WM_QUERYENDSESSION`.
- AppArgs/env/workdir/post-actions work.
- Normal output drain is functionally corrected in the rc1 baseline.
- PowerShellMain remains usable as a reference/fallback for core scenarios but is no longer the preferred mainline.

Before adding new features such as Unicode/raw input, the project should reduce architectural risk by cleaning boundaries, configuration, dead paths, and documentation.

---

## 2. Current architecture

### 2.1 Mainline: CSharpHost

```text
wrapper-csharphost.ps1
  -> loads src/common.ps1
  -> loads user config
  -> Add-Type compiles embedded C# namespace CSharpWrapperHost_v020rc1
  -> C# WrapperHost owns ConPTY/process/signals/output/input lifecycle
  -> PowerShell executes generic PostActions and result output
```

CSharpHost owns:

- ConPTY creation and close;
- process creation with STARTUPINFOEX;
- environment block creation;
- output reader thread;
- input forwarding;
- Ctrl+C routing;
- Ctrl+Break emergency path;
- CTRL_CLOSE_EVENT best-effort;
- hidden window WM_QUERYENDSESSION best-effort;
- timeout/kill;
- normal output drain.

PowerShell owns:

- configuration loading/merging;
- directory preparation;
- post-actions;
- summary and JSON output;
- debug parameters such as `JsonOutputPath` and `PauseOnExit`.

### 2.2 Reference implementation: PowerShellMain

```text
legacy\wrapper.ps1
  -> loads src/common.ps1
  -> PowerShell owns main loop
  -> embedded C# helper owns Win32/ConPTY boundary
```

PowerShellMain passed the base matrix but does not have full Close/Shutdown parity. It should remain as reference/fallback, not as the production mainline.

---

## 3. Core responsibilities vs auxiliary features

### 3.1 Core responsibilities

These define wrapper correctness:

1. Launch app with configured path/args/workdir/env.
2. Provide ConPTY environment.
3. Bridge app terminal output to host console.
4. Forward basic line input.
5. Convert host Ctrl+C to ConPTY ETX `0x03`.
6. Wait for app exit and read exit code.
7. Timeout and kill when configured.
8. Run normal-path PostActions.
9. Handle Close/Logoff/Shutdown as best-effort safety paths.
10. Write wrapper lifecycle logs.

### 3.2 Auxiliary features

These are useful but must not endanger the core:

1. `AppOutputLogFilePath` app terminal output log.
2. ANSI/VT stripping.
3. JSON result file.
4. Timing metrics.
5. Interactive testing helpers.

Important boundary:

```text
AppOutputLogFilePath is auxiliary observability, not a business-grade log.
```

---

## 4. Configuration audit

### 4.1 Current configuration groups

#### Startup

```powershell
AppPath
AppArgs
WorkingDirectory
EnvironmentVariables
InheritParentEnvironment
CreateDirectories
```

Status: keep.

#### Logging/output

```powershell
LogFilePath
AppOutputLogFilePath
OutputEncoding
InputEncoding
StripAnsiSequences
NormalExitOutputDrainMilliseconds
NormalExitOutputQuietMilliseconds
NormalExitClosePseudoConsoleBeforeDrain
```

Status: mostly keep, but review names.

Notes:

- `NormalExitOutputQuietMilliseconds` is fallback only after 0.1.19. It should be documented as fallback, not primary completion logic.
- `NormalExitClosePseudoConsoleBeforeDrain` is useful for testing/rollback but may become internal later.

#### Input

```powershell
InputMode
```

Status: keep, but current supported modes should be explicit:

```text
None
Line
```

`Char` is not production-ready and should not be advertised as fully supported yet.

#### Ctrl+C

```powershell
CtrlCTimeoutSeconds
EnableCtrlCForwarding
EnableCtrlBreakEmergencyExit
KillOnTimeout
```

Status: keep.

#### Close

```powershell
EnableConsoleCloseHandling
CloseAppWaitMilliseconds
CloseHandlerBudgetMilliseconds
CloseReserveMilliseconds
CloseSkipPostActions
```

Status:

- keep close budget options;
- `CloseHideWindowOnClose` has been removed from public configuration because it referred to the visible wrapper console window and was proven unsafe in `CTRL_CLOSE_EVENT`.

#### Shutdown/logoff

```powershell
EnableShutdownSentinel
ShutdownMode
ShutdownAppWaitMilliseconds
ShutdownHandlerBudgetMilliseconds
ShutdownReserveMilliseconds
ShutdownSkipPostActions
```

Status:

- keep `EnableShutdownSentinel`;
- keep independent shutdown budget;
- shutdown priority is hardcoded to `0x3FF` with flags `0` in CSharpHost rc1;
- `ShutdownMode = CancelAndReissue` is not implemented and should be documented as reserved, not supported.

#### Extensions

```powershell
ContentMatcher
PostActions
```

Status: keep as extension points, but `ContentMatcher` is still unused and should be marked reserved.

---

## 5. Code audit

### 5.1 CSharpHost namespace versioning

Current namespace:

```text
CSharpWrapperHost_v020rc1
```

Reason:

PowerShell `Add-Type` cannot unload types in the current process, and same type names can cause stale-code testing. Versioned namespaces solved this during rapid iteration.

Recommendation:

- Keep versioned namespace during active development.
- Before release, consider generating namespace from wrapper version or moving C# to precompiled assembly.
- Document that a new PowerShell process is safest when validating embedded C# changes.

### 5.2 Dead/abandoned paths

Abandoned and already removed:

- `SystemEvents.SessionEnding` router.
- in-handler console hide/minimize.

Still present but disabled/reserved:

- `ShutdownMode = CancelAndReissue`.
- `ContentMatcher`.
- `InputMode = Char` in design/defaults but not production-ready.

Recommendation:

- Mark these as reserved/deprecated in config docs.
- Do not implement them until after stabilization.

### 5.3 Output pump

Current state:

- reader thread reads ConPTY output;
- output queue serializes chunks;
- normal AppExited closes HPCON and drains to EOF/queue empty;
- Close/Shutdown use short best-effort drain.

Risk:

- output pump logic is now correct enough but spread across session, main loop, close handler, and finally.

Recommendation:

- Future refactor: isolate output pump as a dedicated class with explicit states:

```text
Running
ProcessExited
PseudoConsoleClosed
ReaderEof
QueueDrained
Disposed
```

### 5.4 Timing metrics

Current state:

- mostly `DateTime.UtcNow`.

Risk:

- sub-ms paths show `0.000`.

Recommendation:

- Convert interval measurements to `Stopwatch` in a cleanup pass.
- Keep wall-clock timestamps for log line prefixes.

---

## 6. Risk register

| Risk | Severity | Current mitigation | Recommendation |
|---|---:|---|---|
| Close/Shutdown time budget too short for some apps | High | independent budgets | expose per-app config examples |
| Close/Shutdown not guaranteed by OS | High | best-effort wording | keep expectations explicit |
| AppOutputLog mistaken as business log | Medium | documented as auxiliary | keep warning in docs/config comments |
| Unicode/IME input corruption | Medium | documented limitation | future input module |
| Complex TUI unsupported | Medium | non-goal | keep scope narrow |
| Add-Type stale C# type | Medium | versioned namespace | precompiled option later |
| Config surface becoming large | Medium | grouped config | create config reference doc |
| PowerShellMain feature divergence | Low/Medium | reference/fallback positioning | avoid backport unless required |
| Shutdown hidden window behavior differs by host | Medium | VM tests passed | document VM/OS coverage |

---

## 7. Recommended cleanup before new features

### 7.1 Documentation cleanup

Create or update:

```text
docs/reference/CONFIG_REFERENCE.md
```

Should define every config field, default, supported status, and implementation status.

### 7.2 Mark reserved/deprecated options

Candidates:

```text
ShutdownMode=CancelAndReissue reserved
ContentMatcher               reserved
InputMode=Char               reserved/experimental
```

Removed rather than reserved:

```text
CloseHideWindowOnClose       removed; unsafe visible-console UX operation during CTRL_CLOSE_EVENT
```

### 7.3 Logging semantics cleanup

Current C# core logs:

```text
=== Wrapper CSharpHost ended ===
```

before PowerShell post-action timing. Better wording:

```text
=== Wrapper CSharpHost core ended ===
=== Wrapper PowerShell post-actions ended ===
```

This is cosmetic but improves trace readability.

### 7.4 Test split

Current `sample.bulk_output.ps1` assumes normal completion. Create separate config for interrupted bulk output:

```text
sample.bulk_output.ctrlc.ps1
```

This avoids interpreting expected assertion failures as wrapper failures.

### 7.5 CSharpHost release candidate

Before adding Unicode/raw input, freeze CSharpHost as a release candidate:

```text
0.2.0-rc1
```

Candidate criteria:

- base matrix PASS;
- Close PASS;
- Logoff/Shutdown PASS in VM;
- config reference complete;
- known limitations documented.

---

### 7.6 Shutdown priority verification

0.2.0-rc1 verifies `SetProcessShutdownParameters` immediately by calling `GetProcessShutdownParameters` in the same wrapper process and logging requested vs actual values. External verification with `Enter-PSHostProcess` is useful but easy to mis-target: it must attach to the actual wrapper `powershell.exe` process while it is still running, not the outer interactive shell or app process.

### 7.7 RunId and log boundaries

0.2.0-rc1 includes a per-invocation `RunId` generated in the PowerShell entry layer before argument logging. Both PowerShell and C# logs include `[RunId=...]`. This solves append-log ambiguity, especially for `CTRL_CLOSE_EVENT` / shutdown best-effort paths where normal PowerShell post-action end markers may be skipped.

Log phase semantics:

```text
Wrapper PowerShell entry started
  -> AppArgsRaw...
  -> Wrapper CSharpHost core started
  -> CSharpHost core ended OR best-effort completed
  -> PowerShell post-actions ended/skipped when possible
```

`AppArgsRaw` belongs after PowerShell entry start and before CSharpHost core start because it is produced by the PowerShell config/argument preparation layer, not by the C# core.

---

## 8. Recommendation

The architecture review cleanup items have been completed for the 0.2.0-rc1 baseline:

1. `CONFIG_REFERENCE.md` created.
2. `sample.bulk_output.ctrlc.ps1` added.
3. CSharpHost core/post-action log phases clarified.
4. Reserved/removed options documented.
5. Stopwatch timing cleanup completed.
6. CSharpHost tagged as release-candidate baseline.

Current recommendation:

- Do not add new input features during rc validation.
- Use `wrapper-csharphost.ps1` as the mainline.
- Keep `legacy\wrapper.ps1` as reference/fallback.
- Treat Unicode/raw input as a post-rc module.
- Treat app output log as auxiliary observability, not business-grade logging.
