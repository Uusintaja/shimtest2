# Discussion Target Candidates

Purpose: prepare the next major code-hardening discussion by narrowing the field to a small number of high-value directions.

Baseline: post-rc hardening, current working version `0.2.0-rc2-dev`.

This is a working document. It is not a release document and may be edited during discussion phases.

---

## Ranking summary

| Rank | Direction | Why it ranks here |
|---:|---|---|
| 1 | Resource lifecycle hardening | Closest to real reliability risks: ConPTY handles, reader thread, process kill, output drain. |
| 2 | Signal lifecycle hardening | Close/Logoff/Shutdown are complex and recently refactored; remaining router/window edge cases deserve focused review. |
| 3 | Startup diagnostics hardening | Better startup failure reporting improves deployment experience without adding new features. |

Not selected for the next discussion:

- Unicode/raw input: valuable but larger future feature.
- Full output pump state machine: useful if maintainability pain returns, but 0.1.19/0.2.0-rc2-dev behavior is currently passing tests.
- AppOutputLog strictness: auxiliary observability, not core correctness.
- Precompiled C# host: packaging direction, not immediate hardening.

---

## Candidate 1: Resource lifecycle hardening

### Issue 1.1: Dispose / reader thread coordination

Problem:

`ConptySession.Dispose()` may close handles while the output reader thread is still active or blocked in `ReadFile`. Normal AppExited paths are much better after `ClosePseudoConsoleForOutputCompletion`, but abnormal paths and cleanup paths still deserve review.

Why it matters:

- Spurious `[wrapper-reader-error]` can appear in output.
- Reader thread may outlive expected lifecycle briefly.
- Output or diagnostics can be lost in abnormal termination paths.
- Native handle cleanup is a core correctness area.

Discussion questions:

1. Should `Dispose()` explicitly close HPCON/input first, then join reader thread, then close outputRead?
2. Should expected-dispose reader errors be suppressed?
3. What join timeout is acceptable without harming Close/Shutdown best-effort paths?
4. Should normal path and best-effort path use different disposal strategies?

Non-goals for this issue:

- Do not redesign the entire output pump state machine.
- Do not change normal-path output semantics unless required for safe disposal.

---

### Issue 1.2: Timeout/kill path output drain

Problem:

When app ignores Ctrl+C and wrapper kills it, the timeout/kill path may not perform the same output completion flow as normal AppExited. Some output already produced by the child or ConPTY may remain undrained.

Why it matters:

- Timeout/kill is a supported wrapper path, not merely OS best-effort.
- Diagnostics after a killed app are valuable.
- Users may need the last output lines to understand why the app ignored Ctrl+C.

Discussion questions:

1. After `Kill()`, should CSharpHost call `ClosePseudoConsoleForOutputCompletion()`?
2. Should it then call `DrainOutputUntilComplete()` with the normal drain budget or a shorter kill-specific budget?
3. Should this apply to Ctrl+C timeout only, or also Ctrl+Break emergency abort?
4. How do we prevent this from making emergency paths feel slow?

Non-goals for this issue:

- Close/Logoff/Shutdown remain short best-effort paths.
- Do not make AppOutputLog business-grade.

---

## Candidate 2: Signal lifecycle hardening

### Issue 2.1: ShutdownWindowRouter lifecycle after instance refactor

Problem:

`ShutdownWindowRouter` is now instance-based, which is architecturally better than static state. It still deserves focused review around message thread startup, `WM_QUIT`, `Join`, and failure handling.

Why it matters:

- Hidden-window `WM_QUERYENDSESSION` is the key to Logoff/Shutdown behavior.
- If the message thread fails or leaks, shutdown behavior may silently degrade.
- The router depends on Windows Forms and an STA thread.

Discussion questions:

1. Is the current `Start()` timeout behavior acceptable?
2. Should failure to start the sentinel be surfaced as warning only or startup error?
3. Should `Dispose()` wait longer or shorter for the message thread?
4. Are there any remaining static fields or cross-run ownership risks?

Non-goals for this issue:

- Do not implement a Win32-only non-WinForms hidden window in this round.
- Do not implement CancelAndReissue shutdown.

---

### Issue 2.2: ConsoleSignalRouter static trampoline and unsupported concurrency

Problem:

`ConsoleSignalRouter` is now instance-based with a static process-level trampoline. This is the correct direction, but the trampoline remains process-global by necessity.

Why it matters:

- Same-process concurrent `WrapperHost.Run` is intentionally unsupported.
- Sequential same-process runs and parallel independent processes are supported and tested.
- The static trampoline must remain minimal and predictable.

Discussion questions:

1. Is the current rejection of same-process concurrent runs sufficiently clear?
2. Should the rejection path be documented in `CONFIG_REFERENCE`, `RELEASE_CHECKLIST`, or only tests?
3. Does `test-unsupported-concurrent-run.ps1` sufficiently prove safe failure?
4. Should `StaticHandlerInstalled` ever be unregistered, or is process-lifetime installation preferred?

Non-goals for this issue:

- Do not try to support same-process concurrent wrappers.
- Do not change separate-process parallel support.

---

## Candidate 3: Startup diagnostics hardening

### Issue 3.1: PowerShell startup outside structured error result

Problem:

Before CSharpHost runs, the PowerShell entry layer loads config, validates config, initializes directories, compiles embedded C#, logs startup metadata, and builds argument lines. Some of these steps can throw before a normal result object exists.

Why it matters:

- Deployment users need clear startup diagnostics.
- Add-Type failures, bad config paths, invalid config values, or directory permission errors can currently surface as raw PowerShell errors.
- A structured JSON error result would improve automation.

Discussion questions:

1. Should PowerShell entry create a minimal error result before config validation?
2. Should `JsonOutputPath` be honored even for startup/config/Add-Type failures?
3. What fields should a startup-failure JSON include?
4. Should startup failures use exit code `1` while post-action failures use `2` as today?

Non-goals for this issue:

- Do not change CSharpHost runtime behavior.
- Do not add a new config format.

---

### Issue 3.2: Add-Type failure user guidance

Problem:

If embedded C# compilation fails, users may receive a raw compiler or PowerShell error. This is especially relevant because CSharpHost depends on Windows/.NET APIs such as ConPTY P/Invoke and Windows Forms for the shutdown sentinel.

Why it matters:

- Add-Type failure is one of the first failures a new deployment user can hit.
- A raw compiler dump is difficult for operators to act on.
- We can give actionable hints without hiding the original error.

Discussion questions:

1. Should Add-Type be wrapped and logged with friendly hints?
2. Should hints mention Windows PowerShell 5.1, .NET Framework, Windows 10 1809+, and `System.Windows.Forms.dll`?
3. Should failure produce JSON when `JsonOutputPath` is provided?
4. Should Add-Type compile errors be categorized as `StartupFailed` or `ScriptError`?

Non-goals for this issue:

- Do not split the embedded C# into a precompiled binary in this round.
- Do not implement a WinForms-less fallback in this round.

---

## Suggested next discussion

Recommended next discussion target:

```text
Candidate 1: Resource lifecycle hardening
```

Reason:

It is closest to core reliability and native resource correctness. It also has clearer execution boundaries than startup diagnostics and less architectural uncertainty than further signal-router changes.
