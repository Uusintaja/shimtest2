# Current Architecture - CSharpHost 0.2.0-rc1

Audience: developers and maintainers.  
Baseline: 0.2.0-rc1.  
Primary implementation: `wrapper-csharphost.ps1`.

---

## 1. Purpose

The wrapper runs a line-oriented Windows console program inside ConPTY and provides lifecycle/signal governance around it.

Primary goals:

1. Start app with configured args/env/workdir.
2. Bridge app terminal output to host console.
3. Optionally forward basic line input.
4. Forward Ctrl+C as ConPTY ETX `0x03`.
5. Wait for normal app exit and run PostActions.
6. Handle Close/Logoff/Shutdown as best-effort safety paths.
7. Emit wrapper lifecycle logs, RunId, timing, and optional JSON result.

Non-goals:

1. Full TUI support.
2. Raw keyboard / IME / complex Unicode correctness.
3. Strict stdout/stderr separation in ConPTY mode.
4. Business-grade app output logging.
5. Guaranteed cleanup during OS Close/Logoff/Shutdown.

---

## 2. Implementation split

### PowerShell layer

Files:

```text
wrapper-csharphost.ps1
src\common.ps1
```

Responsibilities:

- load and merge config;
- generate RunId;
- log raw AppArgs/env override names;
- compile embedded C# via `Add-Type`;
- call CSharpHost;
- run normal-path PostActions;
- write JSON result;
- show summary.

### C# layer

Embedded namespace:

```text
CSharpWrapperHost_v020rc1
```

Responsibilities:

- ConPTY lifecycle;
- pipe creation and ownership;
- CreateProcess with `STARTUPINFOEX`;
- environment block creation;
- output reader thread;
- input writer;
- Ctrl+C routing;
- Ctrl+Break emergency path;
- console Close best-effort;
- hidden-window Logoff/Shutdown best-effort;
- process wait/kill;
- normal output drain;
- timing logs.

---

## 3. Process model

Typical interactive run:

```text
host powershell.exe / terminal
  -> wrapper-csharphost.ps1
       -> embedded C# WrapperHost
            -> ConPTY / conhost
                 -> app.exe
```

The app does not attach directly to the host console. The wrapper mediates IO and signal flow.

---

## 4. ConPTY IO model

Pipe ownership:

```text
wrapper inputWrite  -> ConPTY inputRead
ConPTY outputWrite  -> wrapper outputRead
```

Output reader:

```text
ConPTY output pipe
  -> C# reader thread
  -> UTF-8 decoder
  -> output queue
  -> host console / optional app output log
```

Important:

`AppOutputLogFilePath` is auxiliary. It is not the app's authoritative business log.

---

## 5. Normal exit path

Normal path includes:

```text
AppExited
Ctrl+C leading to app exit
```

Flow:

```text
process handle signals exit
  -> get exit code
  -> ClosePseudoConsoleForOutputCompletion
  -> reader observes EOF
  -> output queue drains
  -> CSharpHost core returns
  -> PowerShell PostActions
  -> JSON/summary
```

This path is the strongest guarantee path.

---

## 6. Ctrl+C path

Host Ctrl+C flow:

```text
host CTRL_C_EVENT
  -> C# SetConsoleCtrlHandler
  -> signal queue
  -> main loop
  -> write ETX 0x03 to ConPTY input
  -> app receives Ctrl+C semantics if processed input is enabled
  -> wait CtrlCTimeoutSeconds
  -> app exits or wrapper kills on timeout
```

Ctrl+C is the normal graceful-exit route.

---

## 7. Close path

`CTRL_CLOSE_EVENT` is not treated like ordinary Ctrl+C.

Flow:

```text
CTRL_CLOSE_EVENT
  -> C# immediate handler
  -> send ETX 0x03
  -> wait close budget
  -> kill if configured and still running
  -> short best-effort output drain
  -> minimal log
```

PowerShell PostActions/JSON/finally are not guaranteed.

The wrapper deliberately does not hide/minimize/resize the console window in this path.

---

## 8. Logoff / Shutdown path

Implemented through a hidden window receiving:

```text
WM_QUERYENDSESSION
WM_ENDSESSION
```

Flow:

```text
WM_QUERYENDSESSION
  -> C# hidden-window handler
  -> send ETX 0x03
  -> wait shutdown budget
  -> kill if configured and still running
  -> short best-effort output drain
  -> return TRUE, do not cancel OS action
```

The wrapper also calls `SetProcessShutdownParameters` with application first-shutdown level `0x3FF` and verifies it with `GetProcessShutdownParameters`.

---

## 9. Configuration model

Authoritative configuration reference:

```text
docs\reference\CONFIG_REFERENCE.md
```

Important principles:

- Ctrl+C, Close, and Shutdown/Logoff use separate budgets.
- Reserved features are rejected or marked reserved.
- Environment override values are not logged by default.
- Shutdown priority is an internal rc1 implementation choice, not public config.

---

## 10. Logging model

Wrapper log phases:

```text
Wrapper PowerShell entry started
  -> AppArgsRaw / EnvironmentOverrides
  -> Wrapper CSharpHost core started
  -> core event logs
  -> Wrapper CSharpHost core ended OR best-effort completed
  -> PowerShell post-actions ended/skipped when possible
```

Every run gets a RunId.

---

## 11. Accepted limitations

Accepted for rc1:

1. Close/Logoff/Shutdown are best-effort.
2. PowerShell PostActions may not run after system events.
3. `InputMode=Line` is basic line input only.
4. `InputMode=Char` is reserved.
5. `ContentMatcher` is reserved.
6. `ShutdownMode=CancelAndReissue` is reserved.
7. ConPTY output is a terminal stream; stdout/stderr are not separated.
8. App output log is auxiliary.

---

## 12. Future architecture work

Post-rc candidates:

1. Output pump state-machine refactor if maintainability becomes painful.
2. Unicode/raw input module.
3. Optional precompiled C# host packaging.
4. Optional content matcher / auto-response.
5. Optional stdout/stderr separated non-ConPTY mode.
