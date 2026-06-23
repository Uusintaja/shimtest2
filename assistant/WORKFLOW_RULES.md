# Workflow Rules

Purpose: keep the collaboration stable during long-context development.

---

## 1. Phase anchors

Messages may begin with phase markers using the canonical form:

```text
「第 N 轮 [循环] [阶段] [第 M 小轮] 开始|结束」
```

Where:

- `N` = round number (typically increments per major topic shift).
- `[循环]` = optional, may be omitted in practice.
- `阶段` = `讨论` (discussion) or `执行` (execution).
- `第 M 小轮` = optional sub-round index; **atomic discrete batch** within a round.
- `开始|结束` = entry or exit marker.

### 1.1 Top-level phases

| Marker | Meaning |
|---|---|
| `「第 N 轮讨论开始」` | Enter discussion round N |
| `「第 N 轮讨论结束」` | Exit discussion round N |
| `「第 N 轮执行开始」` | Enter execution round N |
| `「第 N 轮执行结束」` | Exit execution round N |

### 1.2 Sub-rounds

Sub-rounds apply to **both** discussion and execution. Each sub-round is an **atomic discrete batch** — it does not "continue" a previous sub-round; you must end the old one and open a new one.

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

### 1.3 Anchor selection

Assistant must use the **latest coherent** phase marker as the primary instruction anchor.

If markers are contradictory, reversed, duplicated, or inconsistent with message content, assistant must **explicitly point out the contradiction before acting**.

Example:

```text
When the user writes "execution start" and "execution end" in reversed order
within the same message, the assistant must first explain the contradiction
and confirm which direction to take before acting.
```

---

## 2. Discussion vs execution

### Discussion phase

Allowed:

- analyze issues;
- compare options;
- propose implementation plans;
- update ROADMAP or CODE_REVIEW_TODO if needed;
- ask for confirmation.

Not allowed unless explicitly permitted:

- modifying wrapper code;
- moving files;
- changing stable docs;
- implementing features.

### Execution phase

Allowed:

- modify files within the confirmed scope;
- update ROADMAP and CODE_REVIEW_TODO;
- provide test commands and expected results.

Do not expand execution scope without asking.

---

## 3. Working documents

### 3.1 Standard working documents

These may be updated frequently, in either discussion or execution phase:

```text
ROADMAP.md            — project state and current step progress
CODE_REVIEW_TODO.md   — code review loop items
```

### 3.2 Assistant-state working documents (parking lot)

`ROADMAP.md`, `CODE_REVIEW_TODO.md`, and `drift_report.md` (at project root)
also serve as **out-of-scope parking lot**:

- When a thought arises in a non-first sub-round that does not fit the
  current round's framework, write it to one of these files.
- Bring the entry up in the next round for analysis.
- These files may be modified at any time, outside the discussion/execution
  framework constraints (they are not subject to max-rounds scope control).

**Equal priority** — choose by scenario, not by priority:

| Scenario | File |
|---|---|
| Project-level "future work" / state | `ROADMAP.md` |
| Code review observations | `CODE_REVIEW_TODO.md` |
| Drift between docs and source | `drift_report.md` |

Rationale: prevents scope creep without losing track of useful observations
that surface during execution.

---

## 4. Fixed documents

Fixed documents should be updated only at phase boundaries or when their current content becomes materially wrong.

Examples:

```text
docs\architecture\architecture_*.md
docs\release\FINAL_SIGNOFF_*.md
docs\release\release_candidate_stabilization.md
```

Do not use fixed docs as scratchpads.

---

## 5. Historical documents

Documents under:

```text
docs\history\
```

are historical. Do not update them as current source of truth except to add legacy notices or archive metadata.

---

## 6. External agent reviews

External agent review is not the default workflow.

Use it only when user explicitly asks.

When external review is used:

- document-review agents should follow `docs\review_agents\DOC_REVIEW_AGENT.md`;
- code-review agents should follow `docs\review_agents\CODE_REVIEW_AGENT.md`;
- assistant must independently judge findings before modifying files.

---

## 7. Code review loop

Use `CODE_REVIEW_TODO.md` to track code hardening loops.

Rules:

1. At the start of each discussion phase, clear or move resolved items out of active sections.
2. Keep unresolved items visible.
3. At the end of discussion, record approved execution items.
4. At the start of execution, read CODE_REVIEW_TODO.md.
5. At the end of execution, update item statuses.

---

## 8. Scope discipline

If user asks for analysis only, do not modify files.

If user asks for execution, modify only the agreed files/areas.

If context is long or ambiguous, prefer asking or explicitly stating assumptions before acting.

---

## 9. Max rounds proposal

To prevent scope creep and runaway context bloat, the assistant proposes a
**max sub-round count** at the start of **each phase's first sub-round**
(both Discussion and Execution), not only at execution sub-round 1.

Inputs to the proposal:

- estimated complexity of the topic;
- project state (how stale working docs are);
- estimated number of file operations;
- whether structural migrations are involved.

Workflow:

- The proposal is part of the current **Discussion** sub-round, not part of
  execution authorization.
- User accepts, adjusts, or rejects.
- Both sides use the agreed number as a **soft constraint**: prefer to
  converge within it, and explicitly justify any overshoot.
- During subsequent sub-rounds, the assistant should **not re-propose** a
  new max-rounds number; doing so defeats the soft-constraint purpose.
- The agreed max-rounds number may still be **updated in working documents**
  (e.g., a note in `ROADMAP.md` if circumstances change materially), but
  this is recorded, not silently changed mid-round.

Rationale: long execution chains blur scope, mix decisions across batches,
and accumulate drift. A pre-committed sub-round count at the start of each
phase forces both sides to converge.
