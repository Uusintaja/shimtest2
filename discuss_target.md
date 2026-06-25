# Discussion Target Candidates

Purpose: prepare the next major code-hardening discussion by proposing
a small number of high-value directions.

Baseline: post-rc hardening, current working version `0.2.0-rc2-dev`.

This is a working document. It is **not** a release document, **not** a
changelog, and **not** a comprehensive issue registry. For detailed
findings with file:line evidence, see
[`/code_review_findings.md`](./code_review_findings.md).

---

## Authoring rules for this file (Lacuna's interpretation, Round 6)

This section explains how this file is structured so that another
assistant (cross-validation partner) or a future round can read it
correctly, propose alternatives, and converge on the next discussion.

### A1. Purpose and scope

This file answers one question:

> **What should we discuss next, and why?**

It is a **planning doc**, not an evidence log. Each candidate is
deliberately scoped to a discussion-friendly size: enough to anchor a
real conversation, not enough to pre-authorize implementation.

It is also explicitly **multi-assistant-aware**: when another agent
proposes a different list, both lists are compared and the user
chooses. The Authoring rules in this section are therefore open to
revision if the user defines a different convention later.

### A2. Size: top 3 directions x top 2 issues each

Default:

```
Top 3 directions x Top 2 issues each = up to 6 issue units
```

If an assistant believes a different shape is appropriate (e.g., 2x3,
or 4x2), they **must** justify the deviation in the Authoring rules
section itself rather than silently expanding.

Justifications I have considered and rejected:
- **4x3 (12 issues)**: too many to discuss in one round; dilutes focus.
- **2x2 (4 issues)**: too few; under-uses the planning slot.
- **3x3 (9 issues)**: skewed; per-direction weight should match.

### A3. Required fields per issue

Each `### Issue N.M` block must contain:

| Field | Purpose |
|---|---|
| **Problem** | What the issue is, stated concretely (1-3 sentences). |
| **Why it matters** | Impact in user-visible or correctness terms. |
| **Discussion questions** | 2-4 questions to anchor the discussion. |
| **Non-goals** | What this issue is **not** about (to bound scope). |

An additional optional field:

- **Severity** (`critical` | `high` | `medium` | `low`) - included by
  the author to signal priority. When two assistants disagree on
  severity, the user resolves.

### A4. What counts as a "direction"

A direction is a coherent area of engineering work, broad enough to
support 2 specific issues but narrow enough that the user can pick
"yes/no" on it. Examples:

- Resource lifecycle hardening (handles, threads, drain, kill)
- Signal lifecycle hardening (router, window, deadlock paths)
- Startup diagnostics hardening (entry-layer error reporting)

A direction should **not** be a single tiny bug unless that bug implies
a broader architectural concern.

### A5. What counts as an "issue"

Each issue under a direction should be:

- **Specific enough** to anchor a discussion (not "improve error
  reporting" but "PowerShell startup has no structured error path").
- **Bounded enough** that non-goals can be listed.
- **Optional in implementation**: this file proposes, execution
  rounds implement.

### A6. Priority criteria (ranking)

Rank candidates by:

1. **Risk to core lifecycle / signal correctness** (release-blocking
   issues first).
2. **Likelihood in supported scenarios** (common scenarios beat
   edge cases).
3. **Impact if it fails** (silent corruption worse than loud error).
4. **Clarity of execution boundary** (well-bounded fixes first).
5. **Value before adding new features** (hardening before enhancement).

Do not prioritize purely stylistic cleanup unless it blocks
comprehension or release confidence.

### A7. What this file does NOT include

- Implementation patches (no code in this file).
- Exhaustive bug lists (those go in `/code_review_findings.md`).
- User-facing instructions (those go in `README.md`).
- Historical bug archaeology unless directly relevant to a candidate.
- Style/naming preferences (those go in `assistant/` docs).

### A8. How to cross-validate another assistant's proposal

When another assistant (e.g., Aster) proposes a different `discuss_target.md`,
compare systematically:

```
1. Are the top 3 directions the same?
2. Is severity annotation used? If so, does it agree?
3. Are the proposed issues root causes or symptoms?
4. Does either list include a release-critical issue the other missed?
5. Does either list over-prioritize accepted limitations or
   auxiliary features?
6. Which candidate has the best risk/reward for the next round?
```

The user makes the final selection. Assistants do not treat this file
as authorization to execute changes.

### A9. Lifecycle of this file

```
Discovery (current or recent code review)
  -> Filing (this file gets a new candidate list)
  -> Cross-validation (user may share with another assistant)
  -> Discussion (next round's Discussion section picks a candidate)
  -> Execution (next round's Execution section addresses it)
  -> Resolution (fix applied; candidate marked "addressed" or
    superseded in next revision of this file)
```

Each round typically rewrites this file in part or in whole. The
complete file should always reflect **what is being discussed or
about to be discussed**, not **what was already done** (that goes in
`docs/release/comparison_report.md` S5).

---

## Ranking summary

| Rank | Direction | Why it ranks here |
|---:|---|---|
| 1 | Resource lifecycle hardening | Includes a **critical** deadlock (Issue 1.1). Release-blocking. Execution boundary is well-defined (handles, drain, kill are localized). |
| 2 | Signal lifecycle hardening | Includes a **high** thread-leak (Issue 2.1) and a **medium** concurrency pair (Issue 2.2). Important but architecturally less brittle than Issue 1.1. |
| 3 | Startup diagnostics hardening | **Medium** issues but high user-visible impact. New deployment users hit this. No architectural risk; pure UX improvement. |

Not selected for the next discussion (with brief reason):

- Perf hardening (FIND-007 StripAnsi regex): auxiliary optimization,
  not core correctness.
- Dead code cleanup (FIND-003, 008, 011): quality of life, no release
  risk.
- Encoding fallback + Add-WrapperError perf (FIND-009, 010): low
  priority.

---

## Candidate 1: Resource lifecycle hardening

### Issue 1.1 (severity: critical): best-effort deadlock on uncaught exception

- **Problem**: In `WrapperHost.Run`, the `bestEffortHandler` delegate
  closes over `running` and `bestEffortStarted`. The handler's `try`
  block sets `running = false` only at the end. If any exception
  propagates out of `try` (e.g., uncaught from `WaitForExit`, `Kill`,
  `GetExitCode`, or config-key access) without being swallowed by an
  inner `try/catch`, control falls to the outer `catch`, which only
  logs. `running` and `bestEffortStarted` are not reset. The main
  loop's `if (bestEffortStarted == 1) { Sleep(30); continue; }` then
  loops forever. The wrapper hangs.
- **Why it matters**: This is a release-critical deadlock. Any single
  exception in the best-effort path leaves the wrapper permanently
  hung. Users see "best-effort path completed" or "best-effort path
  failed" log lines but the process never exits. The sandbox may be
  killed externally, but in interactive runs this means a frozen
  terminal.
- **Discussion questions**:
  1. Should the `try` body be wrapped in a `finally` block that
     unconditionally resets `bestEffortStarted = 0` and `running = false`?
  2. Should inner `try/catch` blocks be added around every operation
     inside the best-effort `try` (SendCtrlC, WaitForExit, Kill,
     GetExitCode, DrainOutputBestEffort)?
  3. After a best-effort failure, should the wrapper attempt a
     secondary recovery (e.g., direct Kill without waiting)?
  4. Should best-effort failures surface a distinct result status
     (`FinalState = "Error"`) in addition to logging?
- **Non-goals**:
  - Do not redesign the entire signal-router architecture.
  - Do not add new best-effort modes (CancelAndReissue remains reserved).
  - Do not change the normal exit path's try/finally structure.

### Issue 1.2 (severity: medium): outputQueue unbounded growth under IO bottleneck

- **Problem**: `ConptySession.outputQueue` (a `ConcurrentQueue<string>`)
  has no size cap. The reader thread enqueues chunks at in-memory
  speed; the drainer is throttled by `OutputDrainLock` contention and
  by `AppendAppOutputLog` performing file IO **inside** that lock.
  When `AppOutputLogFilePath` points to a slow disk or `bestEffortStarted`
  is briefly held, the drainer stalls and the queue grows
  unbounded. Under `bulk_output.exe` (20000 lines x ~50 chars = ~1 MB),
  the queue can accumulate tens of MB within seconds.
- **Why it matters**: Memory pressure + GC pauses + potential OOM in
  pathological cases. Note that this is "auxiliary observability
  overflow" (the `AppOutputLogFilePath` is classified as auxiliary in
  `USER.md` S5 and `architecture_0.2.0-rc1.md` S11), so it is **not**
  release-critical - but it affects long-running wrappers and would
  surface as user-visible "wrapper hung" complaints.
- **Discussion questions**:
  1. Should the queue have a hard cap (e.g., 10 MB total or N
     elements) with drop-oldest on overflow?
  2. Should the overflow count be exposed in the JSON result
     (`result["OutputOverflowCount"]`) so post-mortem analysis can
     see it?
  3. Should `AppendAppOutputLog` move IO out of the lock (use
     `StringBuilder` inside lock, flush outside)?
  4. What is the right threshold (size in bytes vs. count vs. time)?
- **Non-goals**:
  - Do not redesign the output pump state machine.
  - Do not make `AppOutputLog` business-grade.
  - Do not add per-line buffering that could lose ordering.
  - Do not block the reader thread on backpressure (would create a
     bidirectional ConPTY deadlock).

---

## Candidate 2: Signal lifecycle hardening

### Issue 2.1 (severity: high): ShutdownWindowRouter thread leak under early-Dispose race

- **Problem**: `ShutdownWindowRouter.Dispose()` sends `WM_QUIT` via
  `PostThreadMessage` only if `threadId != 0`. If `Dispose` runs before
  the thread has set `threadId` (i.e., before
  `Native.GetCurrentThreadId` in the thread lambda runs), the message
  is skipped. The fallback is a 1-second `Thread.Join(1000)`. If the
  sentinel's `Application.Run()` does not respond to `WM_QUIT` within
  1 second (e.g., because a window message is mid-dispatch), the
  thread leaks. The thread is `IsBackground = true`, so process exit
  eventually cleans up - but the order of cleanup relative to
  `Dispose` is undefined.
- **Why it matters**: `ShutdownWindowRouter` is the **only** path for
  `WM_QUERYENDSESSION`-based Logoff/Shutdown handling. If the
  sentinel thread leaks or stalls, the OS shutdown handshake can
  silently degrade, with no clear log message to indicate why
  shutdown didn't proceed cleanly.
- **Discussion questions**:
  1. Should `Start()` use `Volatile.Write(ref threadId, ...)` to
     publish to the main thread immediately?
  2. Should `Dispose()` use `Volatile.Read(ref threadId)` +
     `Thread.Join(0)` to check liveness before deciding WM_QUIT vs
     Join(timeout)?
  3. Should the sentinel window be forcibly closed (`DestroyWindow`
     / `DestroyHandle`) before the join?
  4. Should the `Start()` timeout (currently 1 second) be
     configurable, or should failure be a hard startup error?
- **Non-goals**:
  - Do not implement a Win32-only non-WinForms hidden window.
  - Do not implement CancelAndReissue shutdown.
  - Do not change the supported `best-effort` semantics for
    Close/Logoff/Shutdown (already documented in
    `architecture_0.2.0-rc1.md` S11).

### Issue 2.2 (severity: medium): ConsoleSignalRouter low-level concurrency gaps

- **Problem**: Two related concurrency issues in `ConsoleSignalRouter`
  and `ResultState`:
  - `disposed` field in `ConsoleSignalRouter` is **not** declared
    `volatile`. `Handle` reads it from a signal-handler thread;
    `Dispose` writes from main thread. JIT may cache the value.
  - `ResultState.TrySetTriggerReason` does **non-atomic**
    check-then-set. Best-effort handler and main-loop normal-exit
    can both pass the check, both write. Last-write-wins, breaking
    the documented "first-wins" semantic.
  - The first is masked in practice by `Current = null` in Dispose
    (the static `StaticHandler` checks `Current` first). The second
    has no mitigation.
- **Why it matters**: The second issue can produce inconsistent
  `TriggerReason` values under concurrent signal/exit paths. The
  first is theoretically a race but is currently masked. Both are
  one-line fixes but indicate a need for a small concurrency pass.
- **Discussion questions**:
  1. Should `disposed` be declared `volatile`? (One-line fix.)
  2. Should `TrySetTriggerReason` use
     `ConcurrentDictionary.TryUpdate` for atomic check-and-set?
  3. Should the `Current` pointer also be `volatile` (defense in
     depth)?
  4. Should we add lightweight stress tests for concurrent
     signal/exit paths?
- **Non-goals**:
  - Do not support same-process concurrent `WrapperHost.Run`
    (already documented as unsupported and tested by
    `scripts/test-unsupported-concurrent-run.ps1`).
  - Do not redesign the signal-router architecture.
  - Do not introduce new signal types.

---

## Candidate 3: Startup diagnostics hardening

### Issue 3.1 (severity: medium): pre-CSharpHost startup has no structured error path

- **Problem**: Before CSharpHost runs, the PowerShell entry layer
  loads the config file (`$userConfig = . $ConfigPath`), merges
  defaults (`Merge-WrapperConfig`), validates
  (`Assert-WrapperConfig`), initializes directories
  (`Initialize-WrapperDirectories`), compiles embedded C#
  (`Add-CSharpHostType`), logs startup metadata, and builds argument
  lines. Some of these steps can throw (e.g.,
  `Assert-WrapperConfig` throws on invalid values, `Add-Type` fails
  on missing references). When this happens, the user sees a raw
  PowerShell error, **not** a structured JSON result.
- **Why it matters**: Deployment users hitting these errors see
  red-text PowerShell dumps, not the JSON their automation expects.
  CI scripts that parse `JsonOutputPath` cannot detect startup
  failures cleanly (the file is never written, exit code is
  unpredictable).
- **Discussion questions**:
  1. Should the PowerShell entry layer create a minimal error
     result BEFORE config validation, so the JSON path always
     works?
  2. Should `JsonOutputPath` be honored even for
     startup/config/Add-Type failures?
  3. What fields should a startup-failure JSON include? (Likely:
     `TriggerReason`, `FinalState`, `Errors`, plus a new
     `StartupStage` field.)
  4. Should startup failures use exit code `1` while post-action
     failures use `2`?
- **Non-goals**:
  - Do not change CSharpHost runtime behavior.
  - Do not add a new config format.
  - Do not add a separate startup-recovery code path.
  - Do not attempt to recover from `Add-Type` failure (e.g., by
     trying a precompiled fallback); fail fast with diagnostics.

### Issue 3.2 (severity: medium): Add-Type failure lacks actionable user guidance

- **Problem**: CSharpHost depends on Windows PowerShell 5.1, .NET
  Framework, and `System.Windows.Forms.dll` (for the shutdown
  sentinel). If embedded C# compilation fails (missing assembly,
  incompatible runtime, syntax error in C#), users receive a raw
  compiler dump. This is the first failure a new deployment user
  can hit - and the dump is hard for operators to act on.
- **Why it matters**: A raw compiler dump doesn't tell the user
  "you need Windows 10 1809+" or "your `System.Windows.Forms.dll` is
  missing". Users can resolve the issue if given actionable hints;
  they cannot if given only the original error.
- **Discussion questions**:
  1. Should `Add-Type` be wrapped in a `try/catch` that logs the
     original error AND a friendly hint set?
  2. Should the hint set mention: Windows PowerShell 5.1, .NET
     Framework, Windows 10 1809+, and `System.Windows.Forms.dll`?
  3. Should the failure produce JSON when `JsonOutputPath` is
     provided?
  4. Should `Add-Type` compile errors be categorized as
     `StartupFailed` vs. `ScriptError`?
- **Non-goals**:
  - Do not split the embedded C# into a precompiled binary.
  - Do not implement a WinForms-less fallback.
  - Do not add a runtime assembly downloader.
  - Do not hide the original compiler error (operators still need
     it for debugging).

---

## Suggested next discussion

**Candidate 1: Resource lifecycle hardening** (specifically **Issue 1.1**).

Reasons:

1. **Severity**: Issue 1.1 is `critical` - a deadlock is a
   release-blocker. Issue 1.2 is `medium` and can ride along.
2. **Execution boundary**: Both issues are localized to
   `WrapperHost.Run` and `ConptySession.Dispose`. A single execution
   sub-round can address them.
3. **Test interaction**: `bulk_output.exe` is the realistic trigger
   for Issue 1.2; Issue 1.1 needs a synthetic test (or a stress
   test) to reproduce.
4. **Architectural risk**: Both fixes are localized; they do not
   require changing the signal-router or startup architectures.

If the user prefers to discuss Signal lifecycle instead, Candidate 2
(Issue 2.1 specifically, the ShutdownWindowRouter thread leak) is the
second-highest priority for the same reasons.
