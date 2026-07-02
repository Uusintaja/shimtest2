# Wrapper Configuration Reference

Baseline version: 0.2.0-rc2-dev  
Primary implementation: `wrapper-csharphost.ps1` / CSharpHost

---

## 1. Principles

1. Configuration is grouped by signal source and responsibility.
2. Ctrl+C, Close, and Shutdown/Logoff use independent timeout budgets.
3. Close/Shutdown are best-effort and intentionally skip normal PostActions by default.
4. `AppOutputLogFilePath` is auxiliary observability, not a business-grade log.
5. Reserved options are documented but not considered production-ready.

---

## 1.1 Status legend

| Status | Meaning |
|---|---|
| Required | Must be provided by user config. |
| Supported | Implemented and tested in rc1. |
| Auxiliary | Useful observability/helper feature; not core correctness. |
| Partially supported | Some values are supported; reserved values are not production-ready. |
| Reserved | Future extension point; do not use in production rc1 configs. |
| Removed | Former idea/key removed from public config. |

## 2. Startup configuration

| Key | Default | Status | Description |
|---|---:|---|---|
| `WrapperVersion` | `"0.2.0-rc2-dev"` | Supported | Wrapper release version string written into JSON result. Users normally do not override it. |
| `AppPath` | `$null` | Required | Full path to wrapped executable. |
| `AppArgs` | `@()` | Supported | Argument list passed to app. Avoid stringly command lines when possible. |
| `WorkingDirectory` | `$null` | Supported | App working directory. Created if needed by sample configs. |
| `EnvironmentVariables` | `@{}` | Supported | Extra/overridden env vars injected into child process. Can override inherited variables such as `APPDATA`, `USERPROFILE`, proxy vars for child only. |
| `InheritParentEnvironment` | `$true` | Supported | Whether child inherits current process env. Overrides in `EnvironmentVariables` win. |
| `LogEnvironmentVariableValues` | `$false` | Supported | Default `$false` logs override names only. When `$true`, values are logged for non-sensitive-looking keys; keys matching pass/pwd/secret/token/key/credential are redacted. |
| `CreateDirectories` | `@()` | Supported | Directories created before launch. |

---

## 3. Logging and output configuration

| Key | Default | Status | Description |
|---|---:|---|---|
| `LogFilePath` | `".\wrapper.log"` | Supported | Wrapper lifecycle log. |
| `AppOutputLogFilePath` | `$null` | Auxiliary | Best-effort app terminal output log. Not business-grade. |
| `OutputEncoding` | `"utf-8"` | Supported | Encoding for ConPTY output decoding and app output log. |
| `InputEncoding` | `"utf-8"` | Supported | Encoding used when writing line input to ConPTY. |
| `StripAnsiSequences` | `$false` | Supported | Strip ANSI/VT for app output log and captured output matching. |
| `NormalExitOutputDrainMilliseconds` | `10000` | Supported | Max normal-path output drain budget after app process exits. |
| `NormalExitOutputQuietMilliseconds` | `250` | Supported | Fallback quiet period if EOF is not observed promptly after normal exit. |
| `NormalExitClosePseudoConsoleBeforeDrain` | `$true` | Supported | After process exit, close HPCON to help reader observe EOF before summary. This is an advanced lifecycle option and normally should not be changed. |

---

## 4. Input configuration

| Key | Default | Status | Description |
|---|---:|---|---|
| `InputMode` | `"Line"` | Supported | `None` and `Line` are supported. `Char` is reserved/experimental and rejected by validation. |

Supported values:

| Value | Status | Meaning |
|---|---|---|
| `None` | Supported | Do not forward host input. |
| `Line` | Supported | Read/edit a line locally, send line on Enter. Basic ASCII line input only. |
| `Char` | Reserved | Intended future immediate char/key forwarding mode. Not production-ready. |

`Line` mode is not a raw keyboard emulator and does not guarantee IME, surrogate pair, combining character, or TUI correctness.

---

## 5. Ctrl+C configuration

| Key | Default | Status | Description |
|---|---:|---|---|
| `EnableCtrlCForwarding` | `$true` | Supported | Capture host Ctrl+C and send ETX `0x03` to ConPTY input. |
| `CtrlCGracePeriodMs` | policy-dependent | Supported | Grace period after forwarding Ctrl+C. If omitted: `Kill` policy uses 5000ms; `Continue` policy uses 1000ms. |
| `CtrlCUnresponsivePolicy` | `"Kill"` | Supported | Action when app does not exit within CtrlC grace period: `Kill` or `Continue`. |
| `EnableCtrlBreakEmergencyExit` | `$true` | Supported | Ctrl+Break is emergency abort, not forwarded as graceful Ctrl+C. |
| `KillOnTimeout` | `$true` | Supported | Kill child on timeout in Ctrl+C/Close/Shutdown paths. |

Ctrl+C unresponsive policy:

```text
Kill      -> timeout kills app and wrapper exits (default)
Continue  -> timeout is logged, Ctrl+C guard resets, wrapper keeps running
```

Related result fields:

```text
CtrlCSentCount          # number of Ctrl+C signals forwarded to ConPTY
CtrlCUnresponsiveCount  # number of Ctrl+C attempts that exceeded the grace period
LastCtrlCSentAt         # wall-clock timestamp of the last forwarded Ctrl+C
```

---

## 6. Close configuration

| Key | Default | Status | Description |
|---|---:|---|---|
| `EnableConsoleCloseHandling` | `$true` | Supported | Handle `CTRL_CLOSE_EVENT` best-effort. |
| `CloseAppWaitMilliseconds` | `2000` | Supported | App wait budget after close signal sends ETX. |
| `CloseHandlerBudgetMilliseconds` | `3000` | Supported | Intended total close handler budget. |
| `CloseReserveMilliseconds` | `800` | Supported | Time reserved for wrapper kill/drain/minimal log. |
| `CloseSkipPostActions` | `$true` | Supported | Skip normal PostActions in Close best-effort path. |

Effective Close wait formula:

```text
effectiveAppWaitMs = min(CloseAppWaitMilliseconds,
                         CloseHandlerBudgetMilliseconds - CloseReserveMilliseconds)
```
---

## 7. Shutdown/logoff configuration

| Key | Default | Status | Description |
|---|---:|---|---|
| `EnableShutdownSentinel` | `$true` | Supported | Enable hidden-window `WM_QUERYENDSESSION` router. |
| `ShutdownMode` | `"BestEffort"` | Supported | Only `BestEffort` is supported in rc1. `CancelAndReissue` is reserved and rejected by validation. |
| `ShutdownAppWaitMilliseconds` | `2000` | Supported | App wait budget after shutdown/logoff sends ETX. |
| `ShutdownHandlerBudgetMilliseconds` | `3000` | Supported | Intended total shutdown/logoff handler budget. |
| `ShutdownReserveMilliseconds` | `800` | Supported | Time reserved for wrapper kill/drain/minimal log. |
| `ShutdownSkipPostActions` | `$true` | Supported | Skip normal PostActions in shutdown/logoff path. |

Effective Shutdown/Logoff wait formula:

```text
effectiveAppWaitMs = min(ShutdownAppWaitMilliseconds,
                         ShutdownHandlerBudgetMilliseconds - ShutdownReserveMilliseconds)
```

---

## 8. Extension configuration

| Key | Default | Status | Description |
|---|---:|---|---|
| `PostActions` | `@()` | Supported | Generic validation/actions after normal path. |
| `ContentMatcher` | `$null` | Reserved | Future output matching/auto-response hook. Not implemented. |

Supported PostActions:

```text
FileExists
FileContentEquals
ExitCodeEquals
RegexOutputContains
CustomPowerShell
```

---

## 9. Recommended minimal configs

### 9.1 Non-interactive text app

```powershell
@{
    AppPath = "C:\path\to\app.exe"
    InputMode = "None"
    LogFilePath = ".\logs\wrapper.log"
    AppOutputLogFilePath = ".\logs\app.output.log"
    StripAnsiSequences = $true
}
```

### 9.2 Interactive line app

```powershell
@{
    AppPath = "C:\path\to\app.exe"
    InputMode = "Line"
    OutputEncoding = "utf-8"
    InputEncoding = "utf-8"
}
```

### 9.3 Shutdown-sensitive app

```powershell
@{
    AppPath = "C:\path\to\app.exe"
    EnableShutdownSentinel = $true
    ShutdownAppWaitMilliseconds = 2000
}
```

---

## 10. Deprecated/reserved summary

| Item | Status | Notes |
|---|---|---|
| `CloseHideWindowOnClose` | Removed | Unsafe visible-console UX operation. |
| `ShutdownMode=CancelAndReissue` | Reserved | Not implemented. Would require explicit shutdown cancellation/reissue design. |
| `ContentMatcher` | Reserved | Future auto-response feature. |
| `InputMode=Char` | Reserved/experimental | Needs separate Unicode/raw input design. |

---

## 11. Shutdown priority verification

CSharpHost 0.2.0-rc1 hardcodes shutdown priority to application first-shutdown level `0x3FF` with flags `0`, then verifies the actual values in the same wrapper process via `GetProcessShutdownParameters`.

Expected log example:

```text
SetProcessShutdownParameters requestedLevel=0x3FF, requestedFlags=0x00000000, setSuccess=True, setLastError=n/a, getSuccess=True, getLastError=n/a, actualLevel=0x3FF, actualFlags=0x00000000, verified=True
```

If an external `Enter-PSHostProcess` script reports `0x280`, first confirm that it attached to the actual wrapper PowerShell process while the wrapper is still running. Attaching to the outer interactive PowerShell host will show that host process's own default shutdown level, not the nested wrapper process.

---

## 12. Test configuration split

`sample.bulk_output.ps1` is for normal completion and expects `bulk-line:19999`.

`sample.bulk_output.ctrlc.ps1` is for interrupted Ctrl+C testing and expects:

```text
TriggerReason = CtrlC
AppExitCode = -1073741510 / 0xC000013A
WasKilled = False
TimedOut = False
```
