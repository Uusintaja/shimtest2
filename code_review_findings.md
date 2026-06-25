# Code Review Findings

> **Purpose**: This file is the **evidence log** for code-level findings
> discovered during wrapper code review. It is distinct from
> `discuss_target.md` (which is a planning doc for next discussion).

---

## Scope: what belongs here vs. elsewhere

| Category | File |
|---|---|
| **Code-level findings** (bugs, races, leaks, perf) — **detailed, evidence-level** | **`/code_review_findings.md`** (this file) |
| Next discussion planning (Aster-style, 3×2 candidates) | `/discuss_target.md` |
| Process-level pitfalls (assistant mistakes in git, plan, docs) | `/PITFALLS.md` |
| Doc-vs-source / doc-vs-doc drift | `/drift_report.md` |
| Project state (Steps, statuses) | `/ROADMAP.md` |
| Code review loop items | `/CODE_REVIEW_TODO.md` |
| Fixed-bug history | `docs/release/comparison_report.md` §5 |

---

## Origin note (Round 5 → Round 6)

This file was created in Round 6 Execution §1 by extracting the FIND
entries from a previous version of `/discuss_target.md` that the author
(Lacuna) had written in Round 5 §2. The motivation was that another
assistant (Aster) proposed using `/discuss_target.md` as a planning doc
following the conventions `top 3 directions × top 2 issues each`. The
detailed FIND entries (11 of them, plus the meta section R1–R8 below)
were moved here to preserve them as evidence.

The original meta rules (R1–R8) still apply to entries in this file, with
one adaptation: this file is the **evidence log**, so the discussion-
centric framing is replaced with the more straightforward "this is a
finding that was discovered".

---

## File rules (Lacuna's interpretation, Round 5 Execution §1)

This section explains how this file is structured so that another
assistant can read it correctly, add new findings, and resolve existing
ones.

### R1. What belongs here

A finding is a concrete, sourceable observation about:

- The **wrapper implementation** (`wrapper-csharphost.ps1`, including
  the embedded C#).
- The **shared PowerShell module** (`src/common.ps1`).
- The **test programs** (`tests/*.c`) — though most test code is small
  and unlikely to harbor bugs.

Every finding must be:

- **Sourceable**: every claim backed by `file:line` reference.
- **Actionable**: at least one plausible fix direction is identified.
- **Distinct** from process pitfalls and doc drift (see table above).

### R2. What does NOT belong here

- **Process pitfalls**: "I forgot to use `git add -A`" → `/PITFALLS.md`,
  not here. These are about the assistant's process, not the code.
- **Doc-vs-source drift**: "architecture doc says namespace is _v020rc1
  but source is _v020rc2dev" → `/drift_report.md`, not here.
- **Feature requests**: "wrapper should support Unicode better" is a
  new feature, not a finding. Goes to design discussion, not here.
- **Working state** of the project: "Step 10.3 is in progress" → `/ROADMAP.md`.
- **Code review loop items** that are not sourceable code issues →
  `/CODE_REVIEW_TODO.md`.

### R3. Entry template (normative)

Each `FIND-NNN` entry MUST use this template. Fields in `[brackets]` are
optional; others are required.

```markdown
### FIND-NNN — <short title, max ~10 words>

- **Severity:** critical | high | medium | low
- **Location:** `path/to/file` line range (required)
- **Category:** bug | resource | race | perf | dead-code | doc-gap
- **Description:** what the issue is, in 1–3 sentences (required)
- **Trigger scenarios:** how the issue manifests in practice (required
  for severity >= medium; recommended for all)
- **Suggested fix direction:** high-level approach, **not the patch**
  (required; the patch is written in a future execution round)
- **Doc gap:** what docs say or don't say about this issue (recommended)
- **Test interaction:** which test programs trigger or could trigger
  (recommended for code-level findings)
- **Source citation:** which round/section of collaboration produced
  this finding (required for provenance)
- **Status:** Open | Resolved | Deferred (default: Open)
```

Do **not** invent new fields without explicit reason. The cross-reference
between assistant-readable clarity and human-readable brevity is
already tight.

### R4. Update discipline

- **Add** new findings with the next available `FIND-NNN` number. Never
  reuse a retired ID.
- **Resolve** by changing `**Status:** Open` to `**Status:** Resolved`
  and appending a `Resolution record:` block at the end of the entry,
  recording the round/section where the fix was applied and a one-line
  summary.
- **Defer** (rare): change `**Status:** Open` to `**Status:** Deferred`
  with a reason. Revisit in a future round.
- **Never delete** entries. They are historical record. Even if a
  finding is superseded by another, keep the original with `**Status:**
  Superseded by FIND-NNN+1` and a note.
- **Never edit retroactively** without a justification note appended at
  the end of the entry (e.g., "re-classified after further analysis in
  Round 7 §2"). Original content must remain readable.

### R5. Severity guidelines

| Severity | When to use |
|---|---|
| **critical** | Causes deadlock, crash, data loss, or security issue. Must fix in the next execution round. |
| **high** | Causes resource leak, incorrect behavior under realistic conditions, or race conditions with non-trivial probability. Should fix soon. |
| **medium** | Performance issue, correctness edge case under unusual conditions, or code-quality issue with maintainability impact. |
| **low** | Dead code, minor inefficiency, stylistic issue, or documentation gap that does not affect behavior. Cleanup. |

**Severity is not permanent.** A finding's severity can be re-classified
during further analysis (e.g., when a low-priority finding turns out to
trigger under common conditions). When re-classifying, append a
justification note per R4.

### R6. Cross-reference conventions

When a finding moves to a different lifecycle stage, **update related
files** rather than duplicating content:

- **Finding becomes a known deployment risk** (i.e., before it is fixed):
  add to `docs/release/ADVISORY_NOTES.md` with reference back to the
  `FIND-NNN` ID.
- **Finding is fixed**: add to `docs/release/comparison_report.md` §5
  as historical record. Update this entry's `**Status:**` to `Resolved`
  and add a Resolution record.
- **Finding reveals a hard constraint** the assistant should always
  respect: add to `assistant/ASSISTANT_ONBOARDING.md` §8 (Hard
  constraints table).
- **Finding is upstream-suppressible** (e.g., test program bug, not
  wrapper bug): update the relevant test program comment if applicable.

### R7. What the assistant should NOT do in this file

- **Do not modify the wrapper code from here.** This file is an evidence
  log, not a fix log. Code changes happen in execution rounds.
- **Do not move findings to other files unilaterally.** Use cross-reference,
  not relocation.
- **Do not invent FIND entries without source code evidence.** Every
  claim must be backed by file:line.
- **Do not retroactively change `Source citation`** (it's historical).
- **Do not break the Summary table sync.** When you add a finding, also
  add a row to the Summary table. When you resolve a finding, update
  both the entry's status AND the table row.

### R8. Expected lifecycle of a finding

```
Discovery (Discussion section of a code-review round)
  → Filing (this file gets a new FIND-NNN entry)
  → Cross-validation (user may share this file with another agent;
    another agent's findings may overlap or contradict)
  → Resolution planning (future Discussion section: design fix)
  → Fix execution (future Execution section: modify code, update
    this entry's Status to Resolved, add Resolution record, propagate
    to comparison_report.md §5)
```

A finding may also be **Deferred** (rare) or **Superseded** (by a
newer finding) — see R4.

---

## How to read this file (for new readers)

After reading the meta section above, readers can navigate the file as:

1. **Title + Origin note** (top of file) — what this file is for and
   where its content came from.
2. **File rules R1–R8** — how entries are structured and maintained.
3. **FIND-001 onwards** — the actual findings, in numeric order. Each
   entry is self-contained; readers do not need to read the meta section
   again for each entry.
4. **Summary table** — quick scan of all findings by ID, severity,
   status.
5. **Cross-reference index** — how this file relates to other docs.
6. **Suggested execution priority** — proposed fix order (the user has
   final say).
7. **How to extend this file** — practical add/resolve instructions.

---

## FIND-001 — best-effort deadlock on exception (CRITICAL)

- **Severity:** critical
- **Location:** `wrapper-csharphost.ps1` lines ~770-820 (the
  `bestEffortHandler` delegate inside `WrapperHost.Run`)
- **Category:** bug (control flow / state machine)
- **Description:** The `bestEffortHandler` delegate sets `running = false`
  only inside its `try` block. If the `try` block throws (uncaught by an
  inner `try`), control transfers to the outer `catch`, which logs but
  does **not** reset `bestEffortStarted` or `running`. The main loop then
  sees `bestEffortStarted == 1` perpetually and loops `Sleep(30); continue;`
  forever, **deadlocking the wrapper**.
- **Trigger scenarios:**
  - `WaitForExit()` throws uncaught exception (rare but possible on
    corrupted handle).
  - Any uncaught exception in the best-effort `try` block
    (e.g., from config key access, dictionary indexing on edge cases).
  - Exception in `Kill()` or `GetExitCode()` not wrapped in inner `try`.
- **Suggested fix direction:** Wrap the `try` body in a `finally` block
  that always resets `bestEffortStarted = 0` and `running = false`. This
  guarantees the main loop can exit even on exception. Inner `try/catch`
  blocks can still log specific errors before the finally runs.
- **Doc gap:** Not mentioned in `ADVISORY_NOTES.md`, `comparison_report.md`
  S5 (fixed bugs), or `architecture_0.2.0-rc1.md` S11 (accepted
  limitations). Completely undocumented.
- **Test interaction:** Hard to verify deterministically. `bulk_output.c`
  with manual close-window could expose it if a race triggers exception
  in the handler. No existing test deliberately triggers this path.
- **Source citation:** Round 5 Discussion S1, item A.1 (Lacuna).
- **Status:** Open

---

## FIND-002 - outputQueue unbounded growth (HIGH)

- **Severity:** high
- **Location:** `wrapper-csharphost.ps1` `ConptySession` class -
  `outputQueue` field (declared as `ConcurrentQueue<string>`, no size
  cap) and `AppendAppOutputLog` (writes under `lock (AppOutputLogLock)`
  - IO inside the lock).
- **Category:** resource (memory leak risk)
- **Description:** The reader thread enqueues output chunks faster than
  the drainer can flush them (when `AppOutputLogFilePath` is slow, when
  `Console.Write` blocks, when `bestEffortStarted == 1` blocks the
  drainer's lock attempt). The queue grows without bound; in pathological
  cases (bulk output + slow disk) memory can balloon to 100+ MB within
  seconds.
- **Trigger scenarios:**
  - `bulk_output.c` (~1 MB output, 20000 lines) + `AppOutputLogFilePath`
    pointing at slow disk / network drive.
  - Output burst during `bestEffortStarted == 1` window (main loop
    skips drain).
  - App that intentionally produces high-volume output (bulk_output.exe
    is a test, but real apps could be worse).
- **Suggested fix direction:** Hard cap on queue size (e.g., 10 MB) +
  drop-oldest strategy when exceeded. Record overflow count in
  `result["OutputOverflowCount"]` for post-mortem. Move IO out of the
  AppOutputLogLock (use StringBuilder inside lock, flush outside).
- **Doc gap:** `ADVISORY_NOTES.md` S9 mentions reader error exposure
  (`[wrapper-reader-error]` message) but does NOT mention queue growth
  as a separate concern. Should be a new advisory.
- **Test interaction:** `bulk_output.c` is the realistic trigger. To
  expose the bug deliberately, point `AppOutputLogFilePath` at a slow
  disk (network share, USB drive) and run bulk_output through the
  wrapper. Verify queue size stays bounded.
- **Source citation:** Round 5 Discussion S1, item B.1 (Lacuna).
- **Status:** Open

---

## FIND-003 - WaitForOutputReaderExit is dead code (LOW)

- **Severity:** low
- **Location:** `wrapper-csharphost.ps1` `ConptySession.WaitForOutputReaderExit(int milliseconds)`
  method definition (~ line 510 of the embedded C#).
- **Category:** dead-code
- **Description:** The method `WaitForOutputReaderExit` is defined but
  has **no callers** in the codebase. `ConptySession.Dispose()` does
  not call it. `WrapperHost.Run()` finally block does not call it. The
  method's existence suggests an intent (wait for reader thread to exit
  before closing handles) that was never wired up. Currently the reader
  thread is `IsBackground = true` so it does not block process exit,
  but its termination order relative to Dispose is undefined.
- **Trigger scenarios:** None - dead code by definition. Cleanup
  benefit: removing or wiring up this method would clarify the reader
  thread lifecycle.
- **Suggested fix direction:** Two options:
  - **a (call it):** Add `WaitForOutputReaderExit(1000)` to
    `ConptySession.Dispose()` before closing handles.
  - **b (delete):** Remove the method if explicit lifecycle management
    is not needed (background thread handles termination at process
    exit).
- **Doc gap:** N/A - dead code does not require documentation.
- **Test interaction:** N/A.
- **Source citation:** Round 5 Discussion S1, item B.2 (Lacuna).
- **Status:** Open

---

## FIND-004 - ShutdownWindowRouter thread leak edge case (HIGH)

- **Severity:** high
- **Location:** `wrapper-csharphost.ps1` `ShutdownWindowRouter.Dispose()`
  method (~ line 365 of the embedded C#).
- **Category:** resource (thread leak under race condition)
- **Description:** `ShutdownWindowRouter.Dispose()` sends `WM_QUIT` via
  `PostThreadMessage` only if `threadId != 0`. If Dispose runs before
  the thread has set `threadId` (i.e., before `Native.GetCurrentThreadId()`
  in the thread lambda runs), the message is skipped. The fallback is a
  1-second `Join(1000)`. If the thread is still alive after 1 second
  (e.g., `Application.Run()` not yet responding to WM_QUIT), the thread
  leaks. Repeated router creation without successful cleanup could
  accumulate leaked threads (though all are `IsBackground = true`, so
  process exit eventually cleans them).
- **Trigger scenarios:**
  - Dispose called immediately after `Start()` (before thread lambda
    runs `GetCurrentThreadId`).
  - `Application.Run()` takes >1s to respond to WM_QUIT.
  - Multiple router creation/destruction cycles in same process.
- **Suggested fix direction:** Use `Volatile.Read(ref threadId)` in
  Dispose to ensure main thread sees the latest value. Or use
  `Thread.Join(0)` first to check liveness, then conditionally
  PostThreadMessage + Join(timeout). Alternatively, force the sentinel
  window to close before joining.
- **Doc gap:** `ADVISORY_NOTES.md` S2 mentions Windows Forms
  dependency for ShutdownWindowRouter but does not detail thread
  synchronization issues.
- **Test interaction:** Hard to test deterministically. Requires
  injecting a delay into the sentinel thread startup.
- **Source citation:** Round 5 Discussion S1, item B.3 (Lacuna).
- **Status:** Open

---

## FIND-005 - `disposed` field not volatile in ConsoleSignalRouter (MEDIUM)

- **Severity:** medium
- **Location:** `wrapper-csharphost.ps1` `ConsoleSignalRouter.disposed`
  field (private, non-volatile).
- **Category:** race (memory visibility)
- **Description:** `Handle` reads `disposed` from a signal-handler
  thread. `Dispose` writes it from the main thread. Without
  `volatile`, the JIT may cache the value, so Handle may run on a
  disposed router. Mitigated in practice by `Current = null` in Dispose
  (the StaticHandler checks Current first) - but the optimization in
  Handle is racy.
- **Trigger scenarios:** Rapid dispose right before signal arrival.
  Unlikely to cause user-visible bug due to Current=null mitigation.
- **Suggested fix direction:** Add `volatile` keyword. One-line change.
- **Doc gap:** N/A - implementation detail.
- **Test interaction:** Hard to test without deliberate memory-model
  testing.
- **Source citation:** Round 5 Discussion S1, item C.2 (Lacuna).
- **Status:** Open

---

## FIND-006 - TrySetTriggerReason non-atomic check-then-set (MEDIUM)

- **Severity:** medium
- **Location:** `wrapper-csharphost.ps1` `ResultState.TrySetTriggerReason`
  method (~ line 695 of embedded C#).
- **Category:** race
- **Description:** The method reads `values["TriggerReason"]`, checks if
  it is null/"Unknown", then writes. Two threads (best-effort handler +
  main loop normal-exit path) can both pass the check, both write. Last
  write wins. The "first-wins" semantic documented in `ResultState` is
  not enforced atomically.
- **Trigger scenarios:** Race between best-effort handler setting
  `TriggerReason = "CtrlClose"/"Shutdown"/"Logoff"` and main loop's
  normal-exit path trying to set `TriggerReason = "AppExited"`.
- **Suggested fix direction:** Use `ConcurrentDictionary.TryUpdate`
  with the predicate "current value is null or 'Unknown'", set new
  value if predicate holds. This is one atomic operation.
- **Doc gap:** N/A - implementation detail.
- **Test interaction:** Hard to test deterministically without
  threading stress testing.
- **Source citation:** Round 5 Discussion S1, item B.4 (Lacuna).
- **Status:** Open

---

## FIND-007 - StripAnsi regex compilation per call (MEDIUM)

- **Severity:** medium
- **Location:** `wrapper-csharphost.ps1` `WrapperHost.StripAnsi` method
  (~ line 1130 of embedded C#).
- **Category:** perf
- **Description:** `Regex.Replace(s, pattern, "")` compiles the regex
  each call. For high-volume output (bulk_output.exe, ~1 MB), 5 regex
  compilations x 20000 lines = significant overhead. Also affects the
  PowerShell `Remove-WrapperAnsiSequences` in `src/common.ps1` (when
  that path is exercised).
- **Trigger scenarios:** `bulk_output.c` with `StripAnsiSequences=$true`.
- **Suggested fix direction:** Precompile patterns as
  `static readonly Regex` fields. Compile-once-use-many.
- **Doc gap:** N/A.
- **Test interaction:** Direct measurement via `bulk_output.c` runs.
- **Source citation:** Round 5 Discussion S1, item C.1 (Lacuna).
- **Status:** Open

---

## FIND-008 - PowerShell-side dead code in `src/common.ps1` (LOW)

- **Severity:** low
- **Location:** `src/common.ps1` functions:
  - `Copy-WrapperHashtable` (~ line 70)
  - `New-WrapperResult` (~ line 215)
  - `Complete-WrapperResult` (~ line 240)
  - `Remove-WrapperAnsiSequences` (~ line 290)
- **Category:** dead-code (under CSharpHost mainline)
- **Description:** These PowerShell functions are not called in the
  CSharpHost path. They are kept for backwards compatibility with
  `legacy/wrapper.ps1` (PowerShellMain) which is now archived per
  USER.md S6. Either remove or move to `legacy/`.
- **Trigger scenarios:** None in current path.
- **Suggested fix direction:**
  - **a Keep:** Leave in `src/common.ps1` for legacy compatibility.
  - **b Move to `legacy/`:** Acknowledges "implementation-neutral"
    contract is no longer in active use.
  - **c Delete:** PowerShellMain is archived; no need for compat.
- **Doc gap:** `src/common.ps1` header comment says "Both implementations
  must use the same config/result schema" but CSharpHost uses its own
  C# schema (`ResultState`). Comment is stale.
- **Test interaction:** N/A.
- **Source citation:** Round 5 Discussion S1, item D.1 (Lacuna).
- **Status:** Open

---

## FIND-009 - `Get-WrapperTextEncoding` no fallback on invalid name (LOW)

- **Severity:** low
- **Location:** `src/common.ps1` `Get-WrapperTextEncoding` (~ line 268).
- **Category:** bug (error handling)
- **Description:** The `default` branch calls
  `[System.Text.Encoding]::GetEncoding($Name)`. If `$Name` is an invalid
  encoding name, this throws `ArgumentException`. The wrapper would
  fail to start with a confusing error.
- **Trigger scenarios:** User config has invalid `OutputEncoding` or
  `InputEncoding`.
- **Suggested fix direction:** Wrap in `try/catch`, fall back to UTF-8
  with a warning log.
- **Doc gap:** N/A.
- **Test interaction:** Direct - set `OutputEncoding = "invalid-name"`,
  run wrapper, observe error.
- **Source citation:** Round 5 Discussion S1, item D.2 (Lacuna).
- **Status:** Open

---

## FIND-010 - `Add-WrapperError` O(n^2) array growth (LOW)

- **Severity:** low
- **Location:** `src/common.ps1` `Add-WrapperError` (~ line 254).
- **Category:** perf
- **Description:** `$Result.Errors += @($Message)` creates a new array
  each call. With N errors, total work is O(N^2). Typical wrapper usage
  has few errors (<10), so impact is negligible.
- **Trigger scenarios:** Massive error count (hundreds). Unlikely in
  practice.
- **Suggested fix direction:** Use `List<string>` instead of array,
  convert to array only at final `result.ToHashtable()` time. Or use
  `ArrayList` (less idiomatic but works in PS 5.1).
- **Doc gap:** N/A.
- **Test interaction:** Synthetic - loop 1000 times, measure.
- **Source citation:** Round 5 Discussion S1, item D.3 (Lacuna).
- **Status:** Open

---

## FIND-011 - `readerThread` never joined (LOW)

- **Severity:** low
- **Location:** `wrapper-csharphost.ps1` `ConptySession.Dispose()`
  method (does not call `readerThread.Join` or
  `WaitForOutputReaderExit`).
- **Category:** resource (mild - relies on background thread)
- **Description:** `Dispose` does not wait for the reader thread to exit.
  The thread is `IsBackground = true`, so process exit will clean up.
  But during wrapper run, the thread could still be reading after
  Dispose returns. Order of cleanup is undefined.
- **Trigger scenarios:** Process exit while reader is mid-ReadFile.
- **Suggested fix direction:** Call `WaitForOutputReaderExit` in
  Dispose (also addresses FIND-003). Or accept the undefined order
  since it's harmless.
- **Doc gap:** N/A.
- **Test interaction:** Hard to observe without process instrumentation.
- **Source citation:** Round 5 Discussion S1, item D.4 (Lacuna).
- **Status:** Open

---

## Summary table

| ID | Severity | Title | Status |
|----|----------|-------|--------|
| FIND-001 | critical | best-effort deadlock on exception | Open |
| FIND-002 | high | outputQueue unbounded growth | Open |
| FIND-004 | high | ShutdownWindowRouter thread leak | Open |
| FIND-005 | medium | `disposed` field not volatile | Open |
| FIND-006 | medium | TrySetTriggerReason non-atomic | Open |
| FIND-007 | medium | StripAnsi regex compilation per call | Open |
| FIND-003 | low | WaitForOutputReaderExit dead code | Open |
| FIND-008 | low | PowerShell-side dead code in common.ps1 | Open |
| FIND-009 | low | Get-WrapperTextEncoding no fallback | Open |
| FIND-010 | low | Add-WrapperError O(n^2) | Open |
| FIND-011 | low | readerThread never joined | Open |

---

## Cross-reference index

- **vs `architecture_0.2.0-rc1.md`**: No finding is mentioned in
  architecture accepted limitations (S11) or future architecture work
  (S12).
- **vs `comparison_report.md` S5** (fixed bugs history): None of the
  13 previously-fixed bugs correspond to these 11 findings - these
  are **new** issues that arose during or after rc1.
- **vs `ADVISORY_NOTES.md`** (10 advisories):
  - S1 (Add-Type static state) - related to runtime compilation, not
    FIND-001/002.
  - S2 (Windows Forms dependency) - partially overlaps with FIND-004
    but does not mention thread sync.
  - S9 (Output reader error exposure) - partially overlaps with
    FIND-002 (related to reader behavior) but does not mention queue
    growth.
  - The other advisories (S3-S8, S10) are unrelated.

**Net effect**: most findings are entirely new and undocumented. ADVISORY_NOTES
should be updated when these are addressed (in future rounds).

---

## Suggested execution priority (future rounds)

| Priority | Finding | Suggested round |
|----------|---------|-----------------|
| P0 | FIND-001 | Round 6+ Execution (must) |
| P1 | FIND-002 | Round 6+ Execution (must) |
| P2 | FIND-004 | Round 7+ Execution |
| P3 | FIND-003 + FIND-011 | Round 7+ Execution (cleanup) |
| P4 | FIND-005, 006, 007 | Round 8+ (perf/quality) |
| P5 | FIND-008, 009, 010 | Round 9+ (low priority) |

**Note**: These are suggestions only. The user has final say on which
findings to address and in what order.

---

## How to extend this file

When new findings are discovered (future code reviews, future
collaborations with other agents, bug reports), append a new `FIND-NNN`
section with the same template (per R3). Update the Summary table at the
bottom. Update the Cross-reference index if related to docs.

When a finding is resolved, change `**Status:** Open` to
`**Status:** Resolved` and append a `Resolution record:` block at the end
of the entry.

When extending the meta section (R1-R8 above), keep the rules tight.
Avoid adding fields or rules that duplicate existing ones. If a new rule
is needed, label it R9, R10, ... and explain why it cannot be subsumed
under existing rules.

Do NOT delete or rewrite existing entries. They are historical record.
