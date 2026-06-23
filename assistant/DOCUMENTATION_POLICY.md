# Documentation Policy

Baseline: 0.2.0-rc1

This document defines how project documentation should be organized and maintained.

---

## 1. Goals

Avoid repeating the failure mode of the old `design_v2.md`, where one document accumulated:

- design goals;
- implementation details;
- bug history;
- config reference;
- user instructions;
- roadmap updates;
- release notes.

Each active document should have one primary audience and one primary purpose.

---

## 2. Document categories

### 2.1 User-facing document

#### `README.md`

Audience: users / operators / first-time testers.

Purpose:

- quick start;
- requirements;
- how to run;
- where to find docs;
- high-level limitations.

Rules:

- Keep short.
- Do not include design history.
- Do not include implementation internals unless necessary for use.

---

### 2.2 Fixed documents

Fixed documents are created at stage boundaries and should not be modified every conversation.

#### Baseline / stage-opening documents

Purpose:

- define what the phase is trying to do;
- define why;
- define intended approach.

Examples:

```text
docs\architecture\architecture_0.2.0-rc1.md
```

#### Stage-closing documents

Purpose:

- summarize what was achieved;
- record deviations from initial assumptions;
- decide whether the stage can close.

Examples:

```text
docs\release\release_candidate_stabilization.md
docs\release\comparison_report.md
```

Rules:

- Update only at meaningful stage boundaries.
- Do not use as scratchpads.

---

### 2.3 Temporary / working documents

These can be edited frequently.

#### Progress / todo documents

Example:

```text
ROADMAP.md
```

Purpose:

- current progress;
- next actions;
- status notes.

#### Review / issue documents

Examples:

```text
docs\architecture\review.md
docs\release\ADVISORY_NOTES.md
```

Purpose:

- record discovered risks;
- record architecture concerns;
- record non-blocking advisory notes;
- track cleanup ideas.

Rules:

- Can be messy.
- Should not be treated as user guidance.
- Important conclusions should later be promoted into a fixed document.

---

### 2.4 Historical documents

Example:

```text
docs\history\design_v2_legacy.md
```

Purpose:

- preserve design evolution;
- preserve bug history;
- explain why certain decisions were made.

Rules:

- Do not treat as current behavior reference.
- Prefer adding a short note pointing to current docs rather than editing history.

---

### 2.5 Assistant-facing documents

Location:

```text
assistant\
```

Audience: AI assistants that drive and maintain this project. Not for end users, operators, or external review agents.

Purpose:

- record collaboration profile;
- record workflow / phase / mode-string protocol;
- record documentation policy itself;
- onboard new project-aware assistants.

Examples:

```text
assistant\README.md                    — short index pointing to the four files below
assistant\USER.md                      — user collaboration profile
assistant\WORKFLOW_RULES.md            — workflow / phase / mode-string protocol
assistant\DOCUMENTATION_POLICY.md      — this document
assistant\ASSISTANT_ONBOARDING.md      — onboarding guide for new project-aware assistants
```

Rules:

- These documents describe the **collaboration protocol**, not project behavior.
- They may be updated when protocol genuinely changes; do not churn them per-task.
- They are **not** subject to user-facing review and not part of release validation.
- External review agents have their own protocol under `docs\review_agents\`.
- `docs\review_agents\` (external agents) and `assistant\` (internal project-aware assistants) must remain separate: their audiences, protocols, and update cadences differ.
- Naming note: this directory was originally named `agent\`; renamed to `assistant\` to avoid collision with the external-agent terminology already established by `docs\review_agents\`.

---

### 2.6 Assistant-state working documents (parking lot)

Location: **project root**, not under `assistant/` or `docs/`.

Examples:

```text
ROADMAP.md              — project state and current step progress
CODE_REVIEW_TODO.md     — code review loop items
drift_report.md         — drift entries between docs and source
```

These are **equal-priority working docs** that may be modified at any time
(both during and outside the discussion/execution framework). They serve a
**dual purpose**:

1. **Primary purpose** — track project state / review items / drift.
2. **Secondary purpose (parking lot)** — absorb out-of-scope thoughts that
   surface mid-execution but don't fit the current round's framework, so they
   can be analyzed in a future round.

**Critical rule:** choose the file by **scenario**, not by priority:

| Scenario | File |
|---|---|
| Project-level "future work" / state | `ROADMAP.md` |
| Code review observations | `CODE_REVIEW_TODO.md` |
| Drift between docs and source | `drift_report.md` |
| Assistant process pitfalls (踩坑记录) | `/PITFALLS.md` (project root, see §2.7) |

Assistant process pitfalls are **explicitly excluded** from `ROADMAP.md`:
project-step status is not the same content as agent-process learnings.
`PITFALLS.md` lives at the project root (alongside `ROADMAP.md`,
`CODE_REVIEW_TODO.md`, `drift_report.md`) precisely because it is a
working document of the same kind — frequently updated, equal priority.

---

### 2.7 Process learnings (agent pitfalls)

Location:

```text
\PITFALLS.md           (project root)
```

Audience: AI assistants (internal project-aware). Records **mistakes the
assistant has made** during prior rounds, with root-cause analysis and
mitigations, so they are not repeated.

**This is distinct from:**

- **Fixed documents** (§2.2) — timeless project truths, not agent history.
- **`ASSISTANT_ONBOARDING.md` §8 hard constraints** — abstract rules
  distilled from the protocol.
- **`drift_report.md`** — discrepancies between **project docs and source code**,
  not between **assistant intent and assistant execution**.

`PITFALLS.md` is for **operational / process** learnings: things like "git
add did not stage modifications because I only added new files" or "renaming
a file broke references because I did not scan markdown".

Rules:

- Each entry has a stable ID (`PIT-NNN`) and explicit status
  (`Open` / `Mitigated` / `Resolved`).
- New entries are appended; old entries are never deleted (status changes
  are recorded instead).
- This file may be modified at any time, like other assistant-state working
  docs.

---

## 3. Source of truth hierarchy

For current 0.2.0-rc1 behavior:

1. `wrapper-csharphost.ps1` and `src\common.ps1` are implementation truth.
2. `docs\reference\CONFIG_REFERENCE.md` is configuration truth.
3. `README.md` is user entry truth.
4. `docs\architecture\architecture_0.2.0-rc1.md` is developer architecture truth.
5. `docs\release\RELEASE_CHECKLIST.md` is release validation truth.
6. `docs\history\*` is not current truth.

---

## 4. Update rules

### When fixing a bug

- Update code.
- Update tests/configs if needed.
- Update `ROADMAP.md` or review notes.
- Do not immediately patch fixed architecture docs unless the bug changes current design.

### When adding a feature

- Create or update a stage-opening design note first.
- Implement.
- Validate.
- Update config reference and README only if user-facing behavior changes.
- Close with a stage summary.

### When external agents report issues

- Fix P0/P1 directly if valid.
- Fix P2 if it affects release clarity or user behavior.
- Do not churn stable docs for low-value style issues.
- Update `docs\review_agents\DOC_REVIEW_AGENT.md` if repeated false positives occur.

---

## 5. Anti-patterns

Avoid:

- turning design docs into changelogs;
- documenting unimplemented features as if available;
- mixing user instructions with bug archaeology;
- treating best-effort paths as guaranteed;
- exposing internal implementation toggles as public config without strong reason;
- editing historical docs as if they were active docs.


---

## 6. Naming rules for fixed documents

Fixed documents must include the relevant phase/version in either the filename or the title, preferably both.

Good examples:

```text
docs\architecture\architecture_0.2.0-rc1.md
docs\release\FINAL_SIGNOFF_0.2.0-rc1.md
docs\release
elease_candidate_stabilization.md  # title must state 0.2.0-rc1
```

Avoid vague names for fixed documents:

```text
current.md
final.md
new_design.md
latest.md
```

Temporary working documents may use broader names when their role is explicitly ongoing, for example:

```text
ROADMAP.md
docs\architecture\review.md
```

Rationale:

Versioned fixed-document names preserve the timeline and prevent future readers from mistaking an old baseline document for the current project state.
