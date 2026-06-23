# User Collaboration Profile

Purpose: preserve user preferences and collaboration style when context becomes long.

---

## 1. Communication style

- User prefers direct, technically rigorous discussion.
- User welcomes clear disagreement when a proposal is wrong or over-engineered.
- User dislikes vague agreement and wants concrete reasoning.
- User values explicit scope control.

---

## 2. Workflow preference

Preferred loop:

```text
Discussion phase
  -> analyze problem
  -> compare options
  -> decide scope
Execution phase
  -> modify only approved scope
  -> update working docs
  -> provide test flow
Feedback phase
  -> user tests on Windows
  -> report logs/results
```

Do not silently execute code changes during a discussion-only phase.

---

## 3. Testing role

- User runs Windows/PowerShell tests locally.
- User provides logs and behavioral feedback.
- Assistant should provide precise test commands and expected results.
- Avoid assuming sandbox execution can validate Windows-specific ConPTY behavior.

---

## 4. Documentation preference

- README is for end users / operators, not for internal design discussion.
- Configuration reference is for config authors.
- Architecture/design docs are for developers.
- Fixed docs should be updated only at phase boundaries.
- Working docs such as ROADMAP and CODE_REVIEW_TODO may be updated frequently.
- Historical docs should not be treated as current truth.

---

## 5. Engineering preference

- Core lifecycle and signal correctness matter more than auxiliary features.
- Avoid over-engineering AppOutputLog or other auxiliary observability.
- Close/Logoff/Shutdown best-effort limitations are accepted and should not be disguised.
- New features should not be mixed into release-candidate stabilization.

---

## 6. Common pitfalls to avoid

- Do not revive external-agent review flow unless user explicitly asks.
- Do not treat PowerShellMain as the mainline.
- Do not modify rc1 frozen behavior unless user explicitly opens a post-rc hardening phase.
- Do not patch fixed docs every turn; use working docs for ongoing notes.
