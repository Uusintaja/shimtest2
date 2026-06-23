# Assistant Process Pitfalls

Purpose: record mistakes the AI assistant has made during prior collaboration
rounds, with root-cause analysis and mitigations, so they are not repeated.

This file is distinct from:

- **Fixed documents** — timeless project truths.
- **`ASSISTANT_ONBOARDING.md` §8 hard constraints** — abstract rules distilled
  from the protocol.
- **`/drift_report.md`** — discrepancies between project docs and source code,
  not between assistant intent and execution.

This file is for **operational / process** learnings only.

Each entry has a stable ID (`PIT-NNN`) and explicit status
(`Open` / `Mitigated` / `Resolved`). New entries are appended; old entries
are never deleted (status changes are recorded instead).

---

## PIT-001 — Partial commit because only new files were `git add`-ed

- **Detected:** 2026-06-23 by Lacuna (Round 2 Execution Sub-round 2)
- **Category:** commit / push
- **Status:** Mitigated
- **Symptom:** First commit message reported "4 files changed, 644
  insertions(+)" but 4 additional modified files (README.md, ROADMAP.md,
  `assistant/DOCUMENTATION_POLICY.md`, `assistant/WORKFLOW_RULES.md`) were
  not captured. They remained as uncommitted working-tree modifications.
- **Root cause:** The assistant called `git add <file1> <file2>` only on
  two untracked files, then `git commit`. `git commit` captures only the
  staged content, so all working-tree modifications that were not explicitly
  added remained uncommitted.
- **Why this matters:** A partial commit produces a misleading commit
  message (file count and insertion count do not match the actual scope).
  Push may proceed but the remote branch will be inconsistent with local
  intent.
- **Mitigation:** Always use `git add -A` (or `git add .`) before commit,
  OR explicitly list every modified file in the `git add` command.
  Verify with `git status --short` immediately before `git commit` to
  confirm no ` M` (unstaged modification) entries remain.
- **Cross-reference:** See also PIT-002 (similar shape: partial change due
  to incomplete planning).

---

## PIT-002 — File move without scanning markdown references

- **Detected:** 2026-06-23 by Lacuna (Round 2 Execution Sub-round 2)
- **Category:** file operations / planning
- **Status:** Mitigated
- **Symptom:** After moving `docs/reference/drift_report.md` to project root
  (`/drift_report.md`), three other documents (`ASSISTANT_ONBOARDING.md`
  §5 / §9 / §12) still referenced the old path. The references were broken
  silently; no compile / lint error caught it because markdown links are not
  validated by git.
- **Root cause:** The structural-migration plan listed the move but did not
  include a "scan and update all markdown references" step. The assistant
  assumed the only relevant file was the one being moved.
- **Why this matters:** Broken references are silent failures. A new
  assistant onboarding will follow a dead link to a file at the old path,
  conclude the file is missing, and lose context.
- **Mitigation:** Before any file move / rename, run
  `grep -rln "<old-path-or-name>" --include="*.md" .` (or equivalent) and
  include the resulting list of references in the execution plan. Update
  them as part of the same sub-round.
- **Cross-reference:** None.

---

## PIT-003 — Wrong write location because DOCUMENTATION_POLICY.md was not consulted

- **Detected:** 2026-06-23 by Lacuna (Round 2 Execution Sub-round 3)
- **Category:** documentation / categorization
- **Status:** Mitigated
- **Symptom:** Assistant proposed writing "parking lot reminders" into
  `ROADMAP.md`. `ROADMAP.md` is project state; the reminders were
  assistant-process pitfalls. The user pointed out the category mismatch
  and noted that `DOCUMENTATION_POLICY.md` §2 had not been kept up to
  reflect the actual categories in use.
- **Root cause:** Before deciding where to write new content, the assistant
  did not consult `assistant/DOCUMENTATION_POLICY.md` §2 to enumerate
  available categories. It also failed to notice that the §2 categories did
  not match the categories the assistant had been using in practice
  (assistant-state working docs, process learnings).
- **Why this matters:** Writing to the wrong category is **silent corruption**
  of a doc. `ROADMAP.md` with embedded assistant-process notes would mislead
  the user (who scans ROADMAP for project steps) into thinking the
  assistant's process mistakes are project steps.
- **Mitigation:** Before writing new content, **read `DOCUMENTATION_POLICY.md`
  §2** to enumerate the available categories. If the right category does
  not exist, **propose a §2 amendment first** rather than improvising a
  location. After this PIT was detected, §2.6 (assistant-state working docs)
  and §2.7 (process learnings) were added to make this category explicit.
- **Cross-reference:** PIT-001, PIT-002.

---

## PIT-004 — Terminology migration: "小轮" → "节"

- **Detected:** 2026-06-23 by Lacuna (Round 3 Discussion)
- **Category:** documentation / language clarity
- **Status:** Mitigated
- **Symptom:** The phrase `第 N 轮 第 M 小轮` contains two `轮` characters
  in close proximity, which can confuse an AI agent parsing the
  canonical mode-string pattern:
  ```text
  「第 N 轮 [循环] [阶段] [第 M 小轮] 开始|结束」
  ```
  The second `轮` is redundant once the first one establishes the
  round-level context; replacing it with `节` (section) eliminates the
  dual-`轮` ambiguity and lowers parse cost.
- **Root cause:** Initial protocol design used `小轮` as the sub-round
  token. The pairing `第 N 轮 ... 第 M 小轮` was readable for humans but
  imposed extra cognitive load on agents segmenting the canonical form.
- **Why this matters:** Mode-string parsing reliability directly affects
  protocol adherence. Any ambiguity in the pattern risks incorrect
  round/section attribution, which can cascade into scope confusion
  (§9 max-rounds mechanics depend on accurate round/section tracking).
- **Mitigation — terminology history note:**
  > "第三轮讨论之前不存在节这个概念，它是由小轮变换而成的，
  > 主要是通过简单的文本替换消除歧义并降低理解门槛"

  Translation: before Round 3 Discussion, the concept of `节` did not
  exist; it was created by transforming `小轮` via plain text substitution.
  The substitution applies to both protocol documents (`WORKFLOW_RULES.md`,
  `ASSISTANT_ONBOARDING.md`) and to the mode-string tokens themselves
  (the canonical form and the parsing regex).

- **Cross-reference:** Migration executed in Round 3 Execution Section 2
  (this entry was added in Section 1 as historical anchor).

---

## PIT-005 — Missed §9 max-rounds proposal at start of round's first section

- **Detected:** 2026-06-23 by Lacuna (Round 3 Discussion Section 2 self-review)
- **Category:** protocol compliance
- **Status:** Mitigated (acknowledged by user as transitional leniency)
- **Symptom:** Round 3 Discussion Section 1 began without the assistant
  proposing a max-section count, even though §9 of `WORKFLOW_RULES.md`
  requires this proposal at the start of each phase's first sub-round.
- **Root cause:** During the ongoing `小轮` → `节` terminology migration,
  the assistant was mentally tracking the new term but had not yet updated
  internal section-numbering habits. The first section of a new round is
  a transition point where protocol execution is most error-prone.
- **Why this matters:** §9 max-rounds is the primary mechanism preventing
  runaway execution chains. Skipping it in a discussion round is lower
  risk than in an execution round (no actual files are changed), but the
  same lapse in execution could lead to unconstrained scope creep.
- **Mitigation:** Treat the start of each phase's first section as a
  **forced checkpoint**: explicitly propose max-rounds before opening any
  topic analysis. If a topic analysis has already begun before this is
  noticed, surface the omission immediately and propose before proceeding
  further (as was done in Round 3 Discussion Section 2).
- **Cross-reference:** Round 3 Discussion Section 2 contains the recovery
  proposal; the user accepted max = 2 for Round 3 Execution.
