# Drift Report — Entries

Purpose: cumulative list of drift entries discovered between project
documents and source code, or between documents at different authority
levels.

This is the **entries file** only. The **protocol** (rules, types, severity,
status workflow, entry template) lives in
[`docs/reference/drift_report_protocol.md`](./drift_report_protocol.md).

This file is a working document; it is appended to frequently. It may be
moved to the project root in a future round — see git history for current
location.

---

## 1. Summary table

Append new entries here. Use the format below; do not edit historical rows.

| ID | Date | Type | Severity | Doc | Source / Other | Status |
|----|------|------|----------|-----|----------------|--------|
| DRIFT-001 | 2026-06-23 | doc-vs-source | high | docs/architecture/architecture_0.2.0-rc1.md | wrapper-csharphost.ps1 | Accepted |
| DRIFT-002 | 2026-06-23 | naming-inconsistency | low | docs/review_agents/DOC_REVIEW_AGENT.md | (project naming convention) | Open |

---

## 2. Entries

### DRIFT-001 — Embedded C# namespace version mismatch between architecture doc and source

- **Type:** `doc-vs-source`
- **Severity:** `high`
- **Status:** Accepted
- **Detected:** 2026-06-23 by AI assistant (initial onboarding).
- **Locations:**
  - Doc: `docs/architecture/architecture_0.2.0-rc1.md` §2 line ~38
  - Source: `wrapper-csharphost.ps1` line 73
- **Discrepancy:**
  - Doc claims namespace = `CSharpWrapperHost_v020rc1`.
  - Source defines namespace = `CSharpWrapperHost_v020rc2dev`.
- **Why this matters:** New readers consulting only the architecture doc will
  believe the embedded C# uses `_v020rc1`, but the current working tree uses
  `_v020rc2dev`. This is misleading if not contextualized.
- **Suggested resolution:** **Accept** — the architecture doc is a fixed
  baseline document describing the frozen `0.2.0-rc1` snapshot. The current
  working tree has legitimately moved past `_v020rc1`. The fix is not to edit
  the fixed doc, but to ensure every reader knows which document describes
  which timestamp. A note to this effect should appear in the architecture doc
  header (deferred until the next phase-boundary update).
- **Resolution record:** Accepted without source/doc modification. Note
  candidate: "Architecture doc describes the 0.2.0-rc1 frozen baseline; the
  current 0.2.0-rc2-dev working tree may have moved namespace/version stamps
  forward. Cross-check with `wrapper-csharphost.ps1` source before acting."

### DRIFT-002 — Project name inconsistency in `docs/review_agents/DOC_REVIEW_AGENT.md`

- **Type:** `naming-inconsistency`
- **Severity:** `low`
- **Status:** Open
- **Detected:** 2026-06-23 by AI assistant (sub-round 3, project-name unification pass).
- **Locations:**
  - Doc: `docs/review_agents/DOC_REVIEW_AGENT.md` line 3 and line 135
  - Source of truth: project naming convention agreed in round 1 discussion
    (`ConPTY Wrapper`).
- **Discrepancy:**
  - `DOC_REVIEW_AGENT.md` uses `ConPTY Generic Wrapper` (old name).
  - After sub-round 3, `README.md`, `ROADMAP.md`,
    `assistant/ASSISTANT_ONBOARDING.md`, and most release docs use
    `ConPTY Wrapper` (new name).
- **Why this matters:** External review agents reading
  `DOC_REVIEW_AGENT.md` will see the old name; minor confusion possible when
  cross-referencing other project docs. The doc is an external-agent entry
  point, so consistency matters more here than in a purely internal doc.
- **Suggested resolution:** Update `DOC_REVIEW_AGENT.md` line 3 and line 135
  to `ConPTY Wrapper`. Out of scope for sub-round 3; to be handled in a
  future execution round (low priority because external review agents are
  not the default workflow).
- **Resolution record:** (pending)
