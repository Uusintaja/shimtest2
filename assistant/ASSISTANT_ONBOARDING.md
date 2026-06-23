# Assistant Onboarding — ConPTY Wrapper

> Audience: AI assistants that drive and maintain the **ConPTY Wrapper** project
> (a PowerShell 5.1 ConPTY wrapper for line-oriented Windows console programs).
> This doc is **not** for end users, operators, or external review agents — see
> `README.md` (project root) and `docs/review_agents/` for those audiences.

---

## 0. TL;DR (30 seconds)

- **What this project is:** a PowerShell 5.1 wrapper around `ConPTY` that runs
  line-oriented console programs and governs their lifecycle (Ctrl+C, Close,
  Logoff, Shutdown, PostActions, JSON results). Mainline is `wrapper-csharphost.ps1`
  (CSharpHost). `legacy/wrapper.ps1` is reference/fallback only.
- **What you are:** the AI assistant that maintains and extends this project.
  Single-agent, project-aware, internal. Distinct from external review agents
  under `docs/review_agents/`.
- **Two non-negotiable rules:**
  1. Read [`assistant/WORKFLOW_RULES.md`](./WORKFLOW_RULES.md) before any
     discussion or execution phase. It defines mode strings, phase discipline,
     and sub-round atomicity.
  2. **Source is truth.** Documentation describes past baselines; if they
     disagree with the source, the source wins.

If you only read one section beyond this TL;DR, read
[`assistant/WORKFLOW_RULES.md`](./WORKFLOW_RULES.md) §1 (phase anchors) and §2
(discussion vs execution).

---

## 1. Project identity

**ConPTY Wrapper** is a PowerShell 5.1 wrapper around Windows `ConPTY`. It runs
a line-oriented console program inside a pseudo console, bridges I/O, forwards
Ctrl+C semantics, handles close/logoff/shutdown best-effort, runs configurable
post-actions, and emits structured JSON results.

It is **not** a TUI library, not a terminal emulator, not a pty server. Its scope
is **process lifecycle + signal correctness**, not full terminal fidelity.

Mainline: `wrapper-csharphost.ps1` (embedded C# namespace
`CSharpWrapperHost_v020rc2dev`).
Reference/fallback: `legacy/wrapper.ps1` (PowerShell-main implementation; not
feature-equivalent; not to be backported unless explicitly requested).

For current project state (what step is in progress, what is validated, what is
pending), always check [`../ROADMAP.md`](../ROADMAP.md) directly — do not trust
a snapshot here.

---

## 2. First-read order

Read in this order. Each tier represents a different time budget.

### 5-minute tier (required for any interaction)

1. [`README.md`](../README.md) — what this project is.
2. [`assistant/USER.md`](./USER.md) — user collaboration preferences.
3. [`assistant/WORKFLOW_RULES.md`](./WORKFLOW_RULES.md) — workflow protocol.
4. [`../ROADMAP.md`](../ROADMAP.md) — current project state.
5. [`../CODE_REVIEW_TODO.md`](../CODE_REVIEW_TODO.md) — active review items.

### 30-minute tier (recommended for substantial work)

6. [`assistant/DOCUMENTATION_POLICY.md`](./DOCUMENTATION_POLICY.md) — doc rules.
7. [`../CODING_GUIDELINES.md`](../CODING_GUIDELINES.md) — coding rules.
8. `docs/architecture/architecture_*.md` (latest) — current architecture baseline.
9. [`../src/common.ps1`](../src/common.ps1) — config + result + PostActions model.
10. [`../wrapper-csharphost.ps1`](../wrapper-csharphost.ps1) — implementation truth.

### Depth tier (read on demand)

- `docs/release/FINAL_SIGNOFF_*.md` — release sign-off.
- `docs/release/ADVISORY_NOTES.md` — non-blocking risks.
- `docs/architecture/review.md` — architecture review notes.
- [`docs/reference/CONFIG_REFERENCE.md`](../docs/reference/CONFIG_REFERENCE.md) — config reference.
- `docs/history/*` — design history. **Never treat as current truth.**

> Use the glob `architecture_*.md` to find the current architecture doc; do not
> read all of them — earlier baselines are historical.

---

## 3. Mode string protocol

This section is a **mirror** of [`assistant/WORKFLOW_RULES.md`](./WORKFLOW_RULES.md) §1 (phase anchors) and §9 (max-rounds proposal). The full content is duplicated here so a new assistant can read the protocol inline during onboarding without bouncing to another file.

If you update one of the two documents, update the other in the same edit.

### 3.1 Canonical form

```text
「第 N 轮 [循环] [阶段] [第 M 小轮] 开始|结束」
```

Where:

- `N` = round number; typically increments per major topic shift.
- `[循环]` = optional; may be omitted in practice.
- `阶段` = `讨论` (discussion) or `执行` (execution).
- `第 M 小轮` = optional sub-round index; an **atomic discrete batch** within a round.
- `开始|结束` = entry or exit marker.

### 3.2 Top-level phase markers

| Marker | Meaning |
|---|---|
| `「第 N 轮讨论开始」` | Enter discussion round N |
| `「第 N 轮讨论结束」` | Exit discussion round N |
| `「第 N 轮执行开始」` | Enter execution round N |
| `「第 N 轮执行结束」` | Exit execution round N |

### 3.3 Sub-round markers

Sub-rounds apply to **both** discussion and execution. Each sub-round is an
**atomic discrete batch** — it does not "continue" a previous sub-round; you
must end the old one and open a new one.

```text
「第 N 轮讨论第 M 小轮开始」   — start a discrete batch in discussion (e.g., opinion feedback)
「第 N 轮讨论第 M 小轮结束」   — end it
「第 N 轮执行第 M 小轮开始」   — start a discrete batch in execution (e.g., primary scope work)
「第 N 轮执行第 M 小轮结束」   — end it
```

Common patterns:

- Discussion sub-round 1: initial topic + proposals.
- Discussion sub-round 2: opinion feedback on sub-round 1.
- Execution sub-round 1: primary scope work.
- Execution sub-round 2+: test feedback revisions or follow-up batches.

### 3.4 Feedback location

Feedback rounds are nested under **Execution**, not Discussion. Rationale:
Feedback typically involves file modifications (updating `../ROADMAP.md`,
recording test results in `../CODE_REVIEW_TODO.md`), which is an
Execution-phase property.

Use the execution sub-round markers with the appropriate M-index. A typical
feedback round is `「第 N 轮执行第 M 小轮开始」` followed by `「第 N 轮执行第 M 小轮结束」`.

### 3.5 Anchor selection rule

Assistant must use the **latest coherent** phase marker as the primary
instruction anchor.

If markers are contradictory, reversed, duplicated, or inconsistent with
message content, assistant must **explicitly point out the contradiction
before acting**.

Example:

```text
When the user writes "execution start" and "execution end" in reversed order
within the same message, the assistant must first explain the contradiction
and confirm which direction to take before acting.
```

### 3.6 Canonical parsing regex

```text
「第\s*\d+\s*轮(\s*循环)?\s*(讨论|执行)(\s*第\s*\d+\s*小轮)?\s*(开始|结束)」
```

Tolerates: optional whitespace, optional `循环`, optional `第 M 小轮`.

### 3.7 Max-rounds proposal (at the start of each phase's first sub-round)

To prevent scope creep and runaway context bloat, the assistant proposes a
**max sub-round count** at the start of **each phase's first sub-round**
(both Discussion and Execution) — not only at execution sub-round 1.

User accepts, adjusts, or rejects the proposal. Both sides use the agreed
number as a soft constraint: prefer to converge within it, explicitly justify
any overshoot.

Do **not** re-propose a new max-rounds number in subsequent sub-rounds of the
same phase; doing so defeats the soft-constraint purpose. The agreed number
may still be **recorded in working documents** (e.g., a note in
`../ROADMAP.md`) if circumstances change materially, but this is recorded,
not silently changed mid-round.

When ad-hoc thoughts arise in **non-first** sub-rounds that do not fit the
current round's framework, write them to one of three equal-priority
assistant-state working docs (`../ROADMAP.md`, `../CODE_REVIEW_TODO.md`, or
`/drift_report.md` at project root) and bring them up in the next round.
These files are not bound by the discussion/execution framework and may be
modified at any time. Choose by scenario, not by priority:

- Project-level "future work" → `../ROADMAP.md`
- Code review observations → `../CODE_REVIEW_TODO.md`
- Drift between docs and source → `/drift_report.md`

The proposal itself is part of the current discussion, not part of execution
authorization — proposing is allowed even mid-discussion.

---

## 4. Phase discipline

| Phase | Allowed | Not allowed (unless explicitly permitted) |
|---|---|---|
| Discussion | analyze / compare / propose / update working docs / ask for confirmation | modify wrapper code / move files / change stable docs / implement features |
| Execution | modify files within confirmed scope / update working docs / provide test commands | expand scope without asking |
| Feedback (nested under Execution sub-rounds) | interpret test results / update working docs to reflect validation | modify files outside approved scope |

### Counter-examples (do NOT do these)

**Bad — discussion-phase silent code change:**
> User says: "analyze how Step 10.3 router refactor handles concurrent Run calls."
> Agent reads source, then quietly rewrites `ConsoleSignalRouter.Register()`.
> **Wrong.** Discussion phase forbids wrapper code modification. Agent should
> report findings only and wait for execution authorization.

**Bad — execution-phase scope creep:**
> User approves scope: "update Step 10.x status in `ROADMAP.md`."
> Agent also rewrites `CODE_REVIEW_TODO.md`, updates `README.md`, and renames
> `agent/` to `assistant/` in the same batch.
> **Wrong.** Execution scope must match what was agreed. Either split into
> multiple execution sub-rounds or ask first.

---

## 5. Source-of-truth hierarchy

For current behavior, in descending order of authority:

1. **`wrapper-csharphost.ps1`** and **`src/common.ps1`** — implementation truth.
2. **`docs/reference/CONFIG_REFERENCE.md`** — configuration truth.
3. **`README.md`** — user entry truth.
4. **`docs/architecture/architecture_*.md`** (latest) — developer architecture truth.
5. **`docs/release/RELEASE_CHECKLIST.md`** — release validation truth.
6. **`docs/history/*`** — **not current truth.**

### Worked example (real drift encountered in this project)

- **Architecture doc** `docs/architecture/architecture_0.2.0-rc1.md` §2 claims
  embedded C# namespace = `CSharpWrapperHost_v020rc1`.
- **Source** `wrapper-csharphost.ps1` line 73 defines namespace =
  `CSharpWrapperHost_v020rc2dev`.
- **Resolution:** source wins (rank 1 > rank 4). The architecture doc describes
  the **0.2.0-rc1 frozen baseline**; the source describes the **0.2.0-rc2-dev
  working tree**. Both are correct at their respective timestamps; the
  architecture doc should not be edited to match the current source because it
  is a fixed baseline document. New drift entries should be filed in
  [`/drift_report.md`](../drift_report.md) (project root, working document).

---

## 6. Communication style

Distilled from [`assistant/USER.md`](./USER.md) §1 + §5:

1. **Direct, technically rigorous.** No filler, no hedging. State findings and
   reasoning.
2. **Welcome clear disagreement.** If a proposal is wrong or over-engineered,
   point it out. Don't soften.
3. **No vague agreement.** Don't say "looks good" or "might work" without
   concrete reasoning. If you agree, explain why.
4. **Explicit scope control.** Don't "do one more thing" beyond the agreed
   scope. If something adjacent is needed, propose it as a separate task.
5. **English-only in project artifacts.** All writes to project files
   (code, docs, configs, logs, commit messages) must be in English. Reply
   language to the user may follow the user's chosen language; these are
   separate.

---

## 7. Engineering preferences

From [`assistant/USER.md`](./USER.md) §5:

1. **Core lifecycle + signal correctness** outranks auxiliary features.
   `AppOutputLogFilePath` is auxiliary observability, not a business-grade log.
   Do not over-engineer it.
2. **Close/Logoff/Shutdown best-effort limitations are accepted.** Do not
   disguise them as guaranteed. Document them in code, docs, and tests as
   best-effort.
3. **No new features during release-candidate stabilization.** If a Step is
   marked "RC", do not mix feature additions into it. Defer to the next
   post-RC step.

---

## 8. Hard constraints

The eight recurring pitfalls. Do not do these.

| # | Pitfall | Source |
|---|---|---|
| 1 | Treat `legacy/wrapper.ps1` (PowerShellMain) as mainline | USER.md §6 |
| 2 | Modify `0.2.0-rc1` frozen behavior without an explicitly opened post-RC hardening phase | FINAL_SIGNOFF §1, USER.md §6 |
| 3 | Patch fixed documents (architecture_*.md, FINAL_SIGNOFF_*.md, release_candidate_stabilization.md) every turn | WORKFLOW_RULES §4, USER.md §6 |
| 4 | Revive external-agent review flow (CODE_REVIEW_AGENT.md / DOC_REVIEW_AGENT.md protocols) without explicit user request | WORKFLOW_RULES §6, USER.md §6 |
| 5 | Treat architecture document as truth and ignore source drift | DOCUMENTATION_POLICY §3 |
| 6 | Silently execute code changes during a discussion-only phase | USER.md §2 |
| 7 | Expand execution scope without asking | WORKFLOW_RULES §2, §8 |
| 8 | Describe best-effort paths (Close / Logoff / Shutdown) as guaranteed | USER.md §5, DOCUMENTATION_POLICY §5 |

The table above captures **abstract protocol rules**. Operational / process
pitfalls the assistant has actually hit during prior rounds are recorded
separately in [`PITFALLS.md`](./PITFALLS.md) (see
[`DOCUMENTATION_POLICY.md`](./DOCUMENTATION_POLICY.md) §2.7). Read PITFALLS.md
periodically to avoid repeating mistakes that have already cost cycles.

---

## 9. What you CAN do autonomously

- Read all project files (docs, source, configs, tests, logs).
- Run static analysis: search, grep, token count, naming consistency checks.
- Cross-validate documents against source code (drift discovery).
- Update working documents: `../ROADMAP.md`, `../CODE_REVIEW_TODO.md`,
  `../docs/architecture/review.md`, `../docs/release/ADVISORY_NOTES.md`,
  [`/drift_report.md`](../drift_report.md) (project root).
- In discussion phase: propose drift fixes, propose refactors, propose
  documentation updates — without modifying files.

---

## 10. What you MUST NOT do autonomously

- Modify `../wrapper-csharphost.ps1` or `../src/common.ps1` without explicit
  execution-phase authorization.
- Modify fixed documents (architecture_*.md, FINAL_SIGNOFF_*.md,
  release_candidate_stabilization.md) without a phase-boundary justification.
- Write to `../legacy/wrapper.ps1` (archived by design).
- Modify `../tests/*.c` (affects test results).
- Introduce new features into a release-candidate stabilization step.
- Run Windows-specific tests yourself (Windows + PowerShell 5.1 + ConPTY is the
  user's environment, not yours).

---

## 11. Testing role

- **User runs tests on Windows.** PowerShell 5.1, Windows 10/11 desktop, with
  pre-compiled test programs in `../bin/`.
- **You provide precise test commands and expected results.** Include exit
  codes, JSON-result field values, log keywords the user should grep for, and
  which `scripts/run-tests.ps1` flag set is appropriate.
- **Do not assume sandbox execution validates Windows-specific ConPTY
  behavior.** Static analysis on your side is fine; runtime validation is the
  user's job.
- **Help interpret logs.** When the user pastes logs or JSON results, parse
  them and identify which lifecycle path was taken (Normal / Ctrl+C / Ctrl+Break
  / Close / Logoff / Shutdown / ScriptError / StartupFailed).

---

## 12. Drift discovery protocol

When source code and documentation disagree, follow this protocol:

1. **Read source first.** It is rank 1 in the truth hierarchy.
2. **Identify the disagreement.** Note the file paths, line numbers, and the
   exact text of each side.
3. **Classify the drift.** Use the type and severity definitions in
   [`docs/reference/drift_report_protocol.md`](../docs/reference/drift_report_protocol.md).
4. **File a drift entry** in [`/drift_report.md`](../drift_report.md) (project
   root) using the template in the protocol file.
5. **Propose a resolution** in discussion phase: update doc to match source,
   update source to match doc (rare; requires explicit user request), or
   accept drift and document the decision.
6. **Do not modify files outside `/drift_report.md`** until the user approves
   the resolution in an execution sub-round.

A worked example is given in §5 above. The protocol and template are in
[`docs/reference/drift_report_protocol.md`](../docs/reference/drift_report_protocol.md);
the cumulative entry list is in [`/drift_report.md`](../drift_report.md).

---

## 13. What this doc does NOT cover

- **Detailed bug history.** See [`../docs/release/comparison_report.md`](../docs/release/comparison_report.md) §5.
- **Test program internals.** See
  [`../docs/reference/TEST_PROGRAMS.md`](../docs/reference/TEST_PROGRAMS.md).
- **Full configuration reference.** See
  [`../docs/reference/CONFIG_REFERENCE.md`](../docs/reference/CONFIG_REFERENCE.md).
- **Historical design documents** (`docs/history/*`). These are preserved for
  context but **must not** be treated as current truth.
- **Current project state snapshot** (which Step is active, which items are
  pending). Always check [`../ROADMAP.md`](../ROADMAP.md) live — this doc would
  rot immediately.
- **External review agent protocols.** See `docs/review_agents/`. They are a
  separate audience with separate protocol; do not confuse them with this one.

---

## Appendix A. Naming note

The directory `assistant/` was originally named `agent/` in the first
draft of this organization. It was renamed to `assistant/` to avoid terminology
collision with `docs/review_agents/` (external agents). The naming rule is
documented in [`./DOCUMENTATION_POLICY.md`](./DOCUMENTATION_POLICY.md) §2.5.

---

## Appendix B. Doc maintenance

- **Update cadence:** when the collaboration protocol genuinely changes,
  not per-task.
- **Owner:** the AI assistant, in coordination with the user.
- **No release-validation role:** this doc is not part of release sign-off.
- **No external review:** external review agents do not review this doc.
