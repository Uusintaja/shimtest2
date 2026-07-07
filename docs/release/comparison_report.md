# ConPTY Wrapper Implementation Comparison Report

Date: 2026-06-17  
Version baseline: 0.2.0-rc1  
Platform under test: Windows PowerShell 5.1 on Windows 10/11 class system

---

## 1. Purpose

This report compares two implementations of the same generic ConPTY wrapper design:

| Implementation | Script | Role |
|---|---|---|
| PowerShellMain | `legacy\wrapper.ps1` | PowerShell owns the main loop/state machine. Embedded C# is used as Win32/ConPTY helper. |
| CSharpHost | `wrapper-csharphost.ps1` | PowerShell owns config and post-actions. Embedded C# owns ConPTY lifecycle, process loop, signal routing, IO, timeout and kill. |

Both implementations share:

- `src/common.ps1`
- the same config model
- the same result model
- the same post-action framework
- the same test programs/configurations

---

## 2. Deployment model

Both current implementations are still single-script style deployments.

### 2.1 PowerShellMain

```text
legacy\wrapper.ps1
  -> loads src/common.ps1
  -> Add-Type compiles embedded C# helper at runtime
  -> PowerShell main loop controls lifecycle
```

### 2.2 CSharpHost

```text
wrapper-csharphost.ps1
  -> loads src/common.ps1
  -> Add-Type compiles embedded C# WrapperHost at runtime
  -> C# controls ConPTY/process/IO/signal lifecycle
  -> PowerShell performs post-actions and reporting
```

No separate persistent `WrapperHost.exe` or `WrapperHost.dll` is required at this stage. C# is embedded in the `.ps1` and compiled on demand by `Add-Type` inside the current PowerShell process.

A future production packaging option may extract the C# host into a precompiled `.exe` or `.dll`, but that is not required for the current test baseline.

---

## 3. Test matrix summary

| Test | Program | Purpose | PowerShellMain | CSharpHost | Notes |
|---|---|---|---:|---:|---|
| T1 | `stdown/app.exe` | Realtime output, Ctrl+C forwarding, env var, file post-action | PASS | PASS | `output.txt=done`; app receives Ctrl+C. |
| T2 | `ignore_ctrlc.exe` | App ignores Ctrl+C; timeout + kill | PASS | PASS | `AppState.WasKilled=True`, `AppState.GracefulExitTimedOut=True`, exit code `-1`. |
| T3 | `bulk_output.exe` | Large output drain and capture | PASS | PASS | `bulk-line:19999` captured. |
| T4 | `exit_code.exe` | AppArgs and exit-code propagation | PASS | PASS | 7, 6, -6 tested after 0.1.7 fix. |
| T5 | `stderr_output.exe` | ConPTY terminal stream includes stdout/stderr | PASS | PASS | Both stdout/stderr patterns captured. |
| T6 | `no_output_sleep.exe` | Long no-output process should not be killed | PASS | PASS | 15-second no-output test passed. |
| T7 | `echo_stdin.exe` | Basic interactive line input forwarding | PASS | PASS | ASCII/basic line input works. |
| T8 | complex Unicode input | IME/surrogate/combining text stress | LIMITED | LIMITED | Deferred; not part of MVP guarantee. |

---

## 4. Important observations

### 4.1 Ctrl+C forwarding works through ConPTY ETX

The core signal chain was validated:

```text
Host Ctrl+C
  -> wrapper SetConsoleCtrlHandler
  -> wrapper writes ETX 0x03 to ConPTY input
  -> ConPTY/control layer interprets it as Ctrl+C control input
  -> target app receives Ctrl+C semantics
```

`stdown.c/app.exe` confirmed this because it does not read stdin. It exits only when its `SetConsoleCtrlHandler` receives `CTRL_C_EVENT`.

### 4.2 Ignored Ctrl+C is handled by timeout + kill

`ignore_ctrlc.exe` intentionally returns `TRUE` from its Ctrl+C handler and keeps running. Both wrappers correctly:

```text
TerminalTrigger.Kind = CtrlC
AppState.State = Killed
AppState.WasKilled = True
AppState.GracefulExitTimedOut = True
AppState.ExitCode = -1 / 0xFFFFFFFF
```

Duplicate Ctrl+C is now handled by recursive-signal guard logging:

```text
Duplicate CTRL_C_EVENT captured while Ctrl+C is already being processed. Ignored by recursive-signal guard.
```

### 4.3 Default Ctrl+C termination produces `0xC000013A`

For programs with no custom Ctrl+C handler, such as `no_output_sleep.exe`, pressing Ctrl+C causes default control-event termination:

```text
AppState.ExitCode = -1073741510
Hex         = 0xC000013A
Meaning     = STATUS_CONTROL_C_EXIT
```

This is not wrapper `Kill()`. It is normal Windows console control-event behavior.

### 4.4 ConPTY output is a terminal stream, not clean stdout

ConPTY output may contain ANSI/VT sequences such as:

- clear screen
- cursor movement
- set title
- erase chars
- show/hide cursor

The wrapper now supports:

```powershell
StripAnsiSequences = $true
```

for app output logs and captured output matching.

### 4.5 stdout/stderr are not naturally separated under ConPTY

`stderr_output.exe` confirmed both streams appear in the terminal output stream. This is expected for ConPTY. A future non-ConPTY pipe mode would be required if strict stdout/stderr separation is a hard requirement.

### 4.6 No-output does not mean hung

`no_output_sleep.exe` was tested with 15 seconds of no output. The wrapper correctly waited for natural process exit and did not kill it.

---

## 5. Bugs found and fixed

### 5.1 Wrong `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE` value

Initial bug:

```text
CreateProcess succeeded, but app exited quickly with 0xC0000142.
```

Cause:

```text
UpdateProcThreadAttribute was passed a pointer-to-HPCON variable instead of the HPCON handle value.
```

Fix:

```csharp
UpdateProcThreadAttribute(..., lpValue: hPC, cbSize: IntPtr.Size, ...)
```

### 5.2 PowerShell 5.1 does not support `` `e`` ESC literal

Initial ANSI stripping used PowerShell 7-style:

```powershell
"`e"
```

Windows PowerShell 5.1 does not support it. Fixed by using:

```powershell
[string][char]27
```

### 5.3 UTF-8 without BOM can corrupt Chinese config strings

A Chinese regex pattern became mojibake under Windows PowerShell 5.1. Mitigation:

- config files should be UTF-8 with BOM if they contain non-ASCII literals;
- test regex patterns prefer ASCII-only strings where possible;
- `sample.stdown.ps1` now checks `Ctrl\+C` instead of Chinese text.

### 5.4 Embedded C# static state persists across script invocations

`Add-Type` loads C# types into the current PowerShell process. Static queues/delegates can persist across multiple script invocations in the same PowerShell session.

Fix:

- `SignalRouter.Register()` drains stale signals;
- `SignalRouter.Unregister()` drains stale signals;
- explicit `Clear()` exists.

### 5.5 Duplicate Ctrl+C logging was misleading

Earlier logs claimed every duplicate Ctrl+C was forwarded. In reality only the first was forwarded. Logs now distinguish:

```text
first Ctrl+C    -> forwarded
later Ctrl+C    -> duplicate ignored
```

### 5.6 PowerShell hashtable dot access is unsafe for config-critical fields

The wrappers now use:

```powershell
$Config["AppArgs"]
```

instead of:

```powershell
$Config.AppArgs
```

for critical config fields.

### 5.7 `$Args` conflicts with PowerShell automatic variable `$args`

A function parameter named `$Args` caused `AppArgsLine` to become empty in Windows PowerShell 5.1 testing.

Bad:

```powershell
function Join-WrapperCommandLineArgs {
    param([object[]]$Args)
}
```

Good:

```powershell
function Join-WrapperCommandLineArgs {
    param([object[]]$ArgumentList)
}
```

### 5.8 Negative exit-code hex formatting in PowerShellMain

Casting `-1` to `[uint32]` failed in Windows PowerShell. Fixed by explicit signed-to-unsigned conversion:

```text
-1 -> 0xFFFFFFFF
-6 -> 0xFFFFFFFA
0xC000013A -> logged correctly
```


### 5.9 Unsafe console hiding inside `CTRL_CLOSE_EVENT`

0.1.9 attempted to call `ShowWindow(GetConsoleWindow(), SW_HIDE)` inside the close handler. Testing showed this can freeze the closing console before ETX `0x03` is delivered to the business process. The app then may not receive Ctrl+C and may be killed without graceful cleanup.

Fix in 0.1.10:

- `CloseHideWindowOnClose` was later removed from public configuration;
- the close handler no longer hides/minimizes the console even if requested;
- close app wait uses dedicated `CloseAppWaitMilliseconds` instead of reusing other timeout concepts;
- Ctrl+C normal path remains independent and now uses `CtrlCGracePeriodMs` / `CtrlCUnresponsivePolicy`.

### 5.10 Interactive test runner pause could be aborted by Ctrl+C

`run-tests.ps1` originally passed `-PauseOnExit` automatically to nested wrappers for interactive tests. Pressing Ctrl+C at nested `Read-Host` could abort the parent test runner.

Fix:

- `run-tests.ps1` no longer enables nested pause automatically;
- `-PauseOnEach` remains opt-in.


### 5.11 Concurrent app-output log writes during Close

`bulk_output.exe` close testing exposed a race: the normal output path and close-handler short drain could write `AppOutputLogFilePath` concurrently, causing a file-in-use `IOException`.

Fix in 0.1.14:

- wrapper log and app output log use process-level locks;
- file streams are opened with `FileShare.ReadWrite`;
- app-output log write errors are best-effort and no longer break the close handler.

### 5.12 Shutdown sentinel disabled in sample configs

Shutdown/logoff tests initially used configs that still contained `EnableShutdownSentinel = $false`, so `ShutdownEventRouter` was registered but disabled. Step 7 configs now enable it by default for sample tests.


### 5.13 Shutdown priority

0.1.17 added `SetProcessShutdownParameters`; rc1 hardcodes level `0x3FF` with flags `0`. This places the wrapper in the application-reserved first-shutdown range so it has a better chance to receive `WM_QUERYENDSESSION` early. It is an ordering hint, not a guarantee.

---

## 6. Known limitations

### 6.1 Close/Shutdown are best-effort

Current baseline handles these signals as best-effort; they are implemented but not guaranteed by the OS:

- `CTRL_CLOSE_EVENT`
- `CTRL_LOGOFF_EVENT`
- `CTRL_SHUTDOWN_EVENT`
- `WM_QUERYENDSESSION`



### 6.2 Unicode/IME/raw input limitations

MVP `InputMode=Line` is not a raw keyboard emulator.

It works for ASCII/basic line input but does not strongly guarantee:

- IME composition;
- surrogate pairs such as `𠮷`;
- combining marks / Zalgo text;
- exact local echo behavior;
- raw `ReadConsoleInput`-style programs.

`echo_stdin.c` was updated to call:

```c
SetConsoleCP(CP_UTF8);
SetConsoleOutputCP(CP_UTF8);
```

but full Unicode input robustness is deferred to a future input-subsystem enhancement.

### 6.3 stdout/stderr separation is not available in current ConPTY mode

ConPTY produces a terminal stream. If strict stdout/stderr separation is required, a separate non-ConPTY pipe mode or hybrid strategy must be designed.

### 6.4 Subprocess tree management is not implemented

Current wrappers manage the primary child process. Job Object-based child process tree control is deferred.

---

## 7. Implementation comparison

| Dimension | PowerShellMain | CSharpHost |
|---|---|---|
| Deployment | Single `.ps1` | Single `.ps1` |
| Runtime C# compilation | Yes | Yes |
| Main lifecycle owner | PowerShell | C# |
| Native resource ownership | Split between PS/C# helper | Mostly C# |
| IO pump | C# reader + PS loop | C# reader + C# loop |
| Signal routing | C# handler + PS loop | C# handler + C# loop |
| Debuggability | Easier to tweak in PS | Cleaner internal state, harder C# edits |
| Stability potential | Medium | Higher |
| Production suitability | Reference/fallback | Preferred mainline |
| Risk | PS runtime edge cases | Add-Type/static-state edge cases |

---

## 8. Recommendation

### 8.1 Preferred mainline

`wrapper-csharphost.ps1` / CSharpHost should become the preferred mainline.

Reason:

1. ConPTY lifecycle, handles, process waiting, signal routing and IO are native-boundary concerns;
2. C# is better suited to `WaitHandle`, threads, `ReadFile`/`WriteFile`, handle cleanup, and state encapsulation;
3. PowerShell remains valuable for configuration, post-actions, deployment convenience and rapid iteration;
4. The deployment model is still simple: a single `.ps1` with embedded C# compiled at runtime.

### 8.2 PowerShellMain role

`legacy\wrapper.ps1` should remain as:

- reference implementation;
- fallback implementation;
- debugging aid;
- proof that the design is not locked into one host architecture.

### 8.3 Future production packaging

After Close/Shutdown and input-subsystem decisions stabilize, consider extracting C# into:

- `WrapperHost.exe`; or
- `WrapperHost.dll` loaded by PowerShell.

Do not do this too early. Runtime-compiled embedded C# is still better during active iteration.

---

## 9. Current next step

The CSharpHost line is prepared as `0.2.0-rc1`. The recommended next step is release-candidate validation and documentation freeze, not new feature development.

Post-rc feature candidates remain:

1. Unicode/raw input module;
2. optional precompiled C# host packaging;
3. optional content matcher / auto-response;
4. optional stdout/stderr separated non-ConPTY mode.


## 10. Scope correction: app output log is auxiliary

Testing `bulk_output.exe` during Close exposed that wrapper-managed app output logging can become complex under high-volume output and asynchronous termination. This report explicitly classifies `AppOutputLogFilePath` as an auxiliary observability feature, not a core correctness guarantee.

Core wrapper responsibilities remain:

1. launch app with configured args/env/working directory;
2. provide ConPTY IO bridge;
3. forward Ctrl+C semantics;
4. wait/timeout/kill according to signal-specific policy;
5. run normal-path post-actions;
6. write wrapper lifecycle logs and structured result when possible.

In Close/Shutdown best-effort paths, app output log completeness and strict ordering are not guaranteed. Business-critical logging must belong to the business program or to a future dedicated audit module.

## 11. Step 7 final result

Step 7 is considered complete for the CSharpHost mainline:

- `CTRL_CLOSE_EVENT` best-effort is validated.
- Hidden-window `WM_QUERYENDSESSION` route is validated for logoff/shutdown/restart in VM testing.
- `SetProcessShutdownParameters(0x3FF, 0)` is added to improve shutdown ordering.
- Close/Shutdown paths use independent budgets and skip normal PostActions.
- Unsafe in-handler window hiding/minimizing is rejected.

PowerShellMain remains a reference/fallback implementation and is not planned to receive full Close/Shutdown backport unless explicitly required.

## 12. Step 8 highest-priority item: normal output drain design

0.1.18 makes normal output drain functional by combining process-exit detection with output queue empty + quiet period. Testing confirms it prevents summary from appearing before pending output. However, the design should be revisited because `OutputEof` from ConPTY is not a reliable immediate completion indicator after child process exit.

The desired model for normal exit should be:

```text
process has exited
  AND
all output already observed by the reader has been delivered to console/log
```

Current quiet-period logic is a pragmatic workaround, not the final design. Step 8 should define a cleaner output-pump completion state, probably centered on process-exit + serialized output queue drain + bounded stabilization, without confusing it with ConPTY EOF.

Timing metrics also need refinement: current `DateTime`-based sub-millisecond measurements often display `0.000`. Step 8 should consider `Stopwatch.GetTimestamp()` / `Stopwatch.Elapsed` for high-resolution intervals.

## 13. Step 8 phase 1 result

Step 8 phase 1 is complete.

0.1.19 changed normal AppExited output drain from a quiet-period-first workaround to a more correct ConPTY lifecycle sequence:

```text
process has exited
  -> ClosePseudoConsoleForOutputCompletion()
  -> reader drains remaining output pipe
  -> reader observes EOF
  -> output queue is drained to console/app-output-log
  -> summary/result is printed
```

Validation results:

| Test | Result | Notes |
|---|---|---|
| stdown Ctrl+C | PASS | `outputEof=True`, `queueEmpty=True`, no 10s stall. |
| bulk_output normal exit | PASS | Summary appears after `bulk-line:19999`; `outputEof=True`, `queueEmpty=True`. |
| bulk_output Ctrl+C | Wrapper-flow PASS | App default exits with `0xC000013A`; normal-completion assertions are not applicable. |
| bulk_output Close | PASS | Best-effort path remains short and stable. |

### AppOutputLog observation

Recent `app.bulk_output.output.log` samples were strictly increasing and had no blank lines. This is not a formal business-log guarantee, but it is a meaningful positive signal: the combination of serialized output dequeue/write and the 0.1.19 normal-drain lifecycle reduces practical ordering races. Still, `AppOutputLogFilePath` remains classified as auxiliary observability. In Close/Shutdown paths it remains best-effort.

## 14. Step 8 phase 2 plan

Do not start Unicode/raw input yet. The next phase is architecture review and cleanup:

1. review current module boundaries;
2. audit configuration count and naming;
3. identify residual code from abandoned approaches;
4. classify core vs auxiliary features;
5. document hidden assumptions and untested edge cases;
6. decide what should be stabilized before adding new functionality.

## 15. 0.1.24 validation update

0.2.0-rc1 validation baseline includes the 0.1.24 validation results:

- Stopwatch timing cleanup works and uses dot decimal formatting.
- RunId log separation works across repeated Ctrl+C and Close runs.
- `args_env` confirms multi-argument injection, env override, and parent env inheritance.
- `LogEnvironmentVariableValues=false` safely logs env override names without values.
- Non-interactive CSharpHost test matrix passes.

This supports moving to a release-candidate stabilization phase.


## 16. Vaultwarden production-like validation

A self-compiled Windows `vaultwarden.exe` was used as a real production-like console service target. The wrapper successfully handled startup, `ENV_FILE` injection, Ctrl+C, Close, Logoff, and Shutdown/restart best-effort paths.

This validation supports the conclusion that CSharpHost 0.2.0-rc1 is suitable for production-like deployment testing of line-oriented service-style console programs.

Template:

```text
configs/vaultwarden.template.ps1
```


## 17. RunRecord schema validation

The flat result schema was replaced in the rc2-dev hardening line by a structured RunRecord model:

```text
Metadata
EventAudit
TerminalTrigger
AppState
WrapperState
PostActions
StdoutBytes
OutputLines
```

Validation result:

- `stdown Ctrl+C` passed.
- `ignore_ctrlc` Kill path passed.
- `ctrlc_counter` Continue path passed.
- Close regression passed.
- `validate-release` passed.

Decision:

- RunRecord model is accepted as successful.
- Minor JSON formatting cosmetics are deferred and are not release/hardening blockers unless they block automation.
