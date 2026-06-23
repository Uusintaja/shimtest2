# Workflow Rules

Purpose: keep the collaboration stable during long-context development.

---

## 1. Phase anchors

The user may start messages with phase markers such as:

```text
「第 N 轮循环讨论开始」
「第 N 轮循环执行第一小轮开始」
「第 N 轮循环执行第二小轮结束」
```

Assistant must use the latest coherent phase marker as the primary instruction anchor.

If markers appear contradictory, reversed, duplicated, or inconsistent with the message content, assistant must explicitly point it out before acting.

Example:

```text
用户写了“执行开始”和“执行结束”顺序矛盾时，先说明矛盾并确认当前应执行什么。
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

These may be updated frequently:

```text
ROADMAP.md
CODE_REVIEW_TODO.md
```

They are allowed in both discussion and execution phases.

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
