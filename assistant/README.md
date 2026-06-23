# Assistant-Facing Documents

This directory contains documents that govern how the AI assistant collaborates
on the **ConPTY Wrapper** project. These documents are **not** for end users,
operators, or external review agents — those audiences have their own entry
points.

## Read order

If you are a new assistant arriving on this project, read in this order:

1. [`ASSISTANT_ONBOARDING.md`](./ASSISTANT_ONBOARDING.md) — onboarding guide.
2. [`USER.md`](./USER.md) — user collaboration preferences.
3. [`WORKFLOW_RULES.md`](./WORKFLOW_RULES.md) — workflow / phase / mode-string protocol.
4. [`DOCUMENTATION_POLICY.md`](./DOCUMENTATION_POLICY.md) — doc organization rules.

## Notes

- These documents describe the **collaboration protocol**, not project behavior.
- They may be updated when the protocol genuinely changes; do not churn them
  per-task.
- They are **not** subject to user-facing review and not part of release
  validation.
- External review agents have their own protocol under `../docs/review_agents/`.
  Do not confuse the two audiences.

## Naming history

This directory was originally named `agent/` in the first draft. It was
renamed to `assistant/` to avoid terminology collision with
`docs/review_agents/` (external agents). See
[`DOCUMENTATION_POLICY.md`](./DOCUMENTATION_POLICY.md) §2.5 for the rule.
