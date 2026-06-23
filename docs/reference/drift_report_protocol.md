# Drift Report Protocol

Purpose: define the rules for classifying, filing, and resolving drift between
project documents and source code, or between documents at different authority
levels.

This document is the **protocol only**. Actual drift entries live in a
separate file: see [`/drift_report.md`](../drift_report.md) (project root,
working document, updated frequently as drift is discovered).

Read this once to understand the system; reference it when filing or
triaging entries. This file is read by **both** internal project-aware
assistants (see [`../assistant/ASSISTANT_ONBOARDING.md`](../assistant/ASSISTANT_ONBOARDING.md)
§12) and external review agents (see `../docs/review_agents/`).

---

## 1. Drift types

| Type | Meaning |
|---|---|
| `doc-vs-source` | A document disagrees with the source code. |
| `doc-vs-doc` | Two documents disagree with each other (excluding history). |
| `working-doc-staleness` | A working document (`../ROADMAP.md`, `../CODE_REVIEW_TODO.md`, etc.) does not reflect the latest validated state. |
| `naming-inconsistency` | Naming conventions drift across files (e.g., old vs new project name, old vs new namespace). |
| `version-stamp-rot` | A version-stamped fixed document still claims an outdated baseline without an explicit "historical" marker. |

---

## 2. Severity levels

| Level | Meaning |
|---|---|
| `critical` | Affects user-visible behavior or correctness (wrong command, misleading config, unsafe assumption). |
| `high` | Misleads new readers / assistants but does not affect current use. |
| `medium` | Inconsistency between documents, not directly misleading. |
| `low` | Naming or formatting inconsistencies; safe to defer. |

---

## 3. Status workflow

```text
Open ──► Triaged ──► { Resolved | Accepted | Deferred }
```

- **Open** — drift identified, not yet assessed.
- **Triaged** — severity + type assigned; resolution path proposed.
- **Resolved** — fix applied (one side updated to match the other).
- **Accepted** — drift acknowledged as intentional (e.g., fixed baseline doc
  intentionally describes the past, not the present).
- **Deferred** — fix postponed; revisit later.

---

## 4. Entry template

Use this template for each new drift entry. Place the rendered entry in the
entries file (see header above), and append a one-line summary to that file's
summary table.

```markdown
### DRIFT-NNN — <short title>

- **Type:** `<type>` (see §1)
- **Severity:** `<severity>` (see §2)
- **Status:** Open / Triaged / Resolved / Accepted / Deferred
- **Detected:** YYYY-MM-DD by <detector>
- **Locations:**
  - Doc: `<path>` §X.Y or line LLL
  - Source / other: `<path>` line LLL or §X.Y
- **Discrepancy:** (quote or paraphrase the two sides)
- **Why this matters:** (one or two sentences on impact)
- **Suggested resolution:** (update doc / update source / accept / defer)
- **Resolution record:** (filled when status moves to Resolved or Accepted;
  record the commit hash and a one-line summary)
```

---

## 5. How to file an entry

- **Discover drift** by reading source first (per
  [`../assistant/ASSISTANT_ONBOARDING.md`](../assistant/ASSISTANT_ONBOARDING.md) §5
  source-of-truth hierarchy), then comparing against documents.
- **Identify the disagreement.** Note the file paths, line numbers, and the
  exact text of each side.
- **Classify the drift** using the type and severity definitions in §1 and §2.
- **File the entry** in the entries file using the §4 template.
- **Propose a resolution** in discussion phase: update doc to match source,
  update source to match doc (rare; requires explicit user request), accept
  drift and document the decision, or defer.
- **Do not modify files outside the entries file** until the user approves
  the resolution in an execution sub-round.

---

## 6. How to use the entries file

- **Add entries** when you discover drift. Use the next available
  `DRIFT-NNN` number.
- **Update statuses** when resolutions are applied or accepted.
- **Do not delete** historical entries; resolve them with the Status field.
- **Do not duplicate** drift across multiple entries; if the same root cause
  appears in multiple files, file one entry and reference all locations.
- **Treat the entries file as a working document** alongside `../ROADMAP.md`
  and `../CODE_REVIEW_TODO.md`. It may be edited frequently.

---

## 7. Files involved

- **This file** (`docs/reference/drift_report_protocol.md`) — protocol, rules,
  rarely updated.
- **Entries file** (`/drift_report.md` at project root) — cumulative list of
  drift entries, frequently appended.
- **Cross-references:**
  - `../assistant/ASSISTANT_ONBOARDING.md` §12 — assistant drift discovery
    protocol.
  - `../docs/release/ADVISORY_NOTES.md` — non-blocking risks (separate but
    related).
  - `../CODE_REVIEW_TODO.md` — code review items (separate but related).

These three working-doc locations (`/drift_report.md`, `../ROADMAP.md`,
`../CODE_REVIEW_TODO.md`) are **equal priority** under the assistant-state
parking lot convention. Choose by scenario, not by priority:

- **Drift entries** → `/drift_report.md`
- **Project-level "future work"** → `../ROADMAP.md`
- **Code review observations** → `../CODE_REVIEW_TODO.md`
