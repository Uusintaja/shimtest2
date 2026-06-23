# PAT Collaboration Guide

Purpose: document the GitHub Personal Access Token (PAT) workflow used by
the AI assistant (Lacuna) to push commits to the project's remote working
branch.

This document is read by AI assistants only (see
[`./DOCUMENTATION_POLICY.md`](./DOCUMENTATION_POLICY.md) §2.5). It is **not**
a user-facing document; users do not need to read it unless they are
configuring or rotating the PAT.

---

## 1. Why a PAT

The AI assistant runs in a sandboxed environment with no pre-existing
GitHub credentials. To push commits without requiring the user to forward
every push manually, a short-lived Personal Access Token (PAT) is granted
once per collaboration period and stored in a file outside the repository
tree.

The user retains final authority over GitHub credentials. The assistant
**never** pushes to `main` directly; all assistant-driven pushes go to
explicitly whitelisted branches (see §3).

---

## 2. Token lifecycle

| Phase | Duration | Storage |
|---|---|---|
| Active | 7 days from generation | `/home/user/uploads/P7AT.txt` (read-on-demand) |
| Rotation | Before expiration | User generates a new PAT and updates the file |

The assistant does **not** store the PAT anywhere inside the repository
tree. The PAT file path is `/home/user/uploads/P7AT.txt` by convention;
the assistant reads it on demand and discards any temporary copies after
use.

---

## 3. Whitelisted branches (safety boundary)

Only branches in the GitHub branch-protection whitelist can be pushed to.
The whitelist is configured by the user via GitHub repository settings;
the assistant does **not** modify it.

Expected behavior:

| Target branch | Expected result |
|---|---|
| Whitelisted (e.g., `rc2test`) | Push succeeds |
| Not whitelisted (e.g., `dev-test`) | Push rejected with `GH013: creations being restricted` |

This whitelist serves as the **safety boundary** between the assistant's
working area (`rc2test` in current practice) and the protected `main`
branch. Even if the PAT technically permits pushing to `main`, the
assistant **must not** do so — `main` merges are the user's manual
responsibility.

---

## 4. Standard push workflow

The assistant's standard push sequence (verified working in Round 2
Execution Section 1):

1. **Read PAT** from `/home/user/uploads/P7AT.txt`. Mask the display:
   show only length, first 4 characters, and last 4 characters.

   ```
   PAT length: 93 chars
   Prefix: gith...
   Suffix: ...Wy55
   ```

2. **Create a temporary credential file** at `/tmp/.git-credentials-*`:
   ```
   https://x-access-token:<PAT>@github.com
   ```
   Set `chmod 600` on the file. **Never** use a path inside the repo.

3. **Configure credential helper** for the push operation only:
   ```
   git -c credential.helper="store --file=<cred-file>" push origin <branch>
   ```
   Do **not** modify global git config; use `-c` for one-shot config.

4. **Push** to the target branch (whitelisted).

5. **Clean up** the credential file immediately after the push:
   ```
   rm -f /tmp/.git-credentials-*
   ```

The credential file is never committed, never logged, and never written
to any file inside the repository tree.

---

## 5. Git identity

Git commits require `user.name` and `user.email`. The assistant sets a
local-only identity for the repository:

```
git config --local user.name "shimtest2-assistant"
git config --local user.email "shimtest2-assistant@local"
```

This identity is clearly marked as the assistant's and is **not** the
repository owner's identity. If the user wishes to attribute commits to
their own identity, they should explicitly instruct the assistant to
update `git config --local user.{name,email}`.

Note: if a remote URL has changed (e.g., `.git/config` was wiped as
described in §6 below), re-apply:
```
git remote add origin https://github.com/Uusintaja/shimtest2.git
git branch --set-upstream-to=origin/main main
```

---

## 6. Pitfalls we've hit in PAT workflow

### PIT-equivalent 1 — `.git/config` rewrite after `git config --local`

- **Symptom:** After running `git config --local credential.helper "..."`,
  the `.git/config` file may be reduced from ~300 bytes (with `[remote
  "origin"]`, `[branch "main"]`, `[core]`) to ~73 bytes (only the newly
  added credential helper section). This breaks `git ls-remote origin`,
  which then errors with `fatal: 'origin' does not appear to be a git
  repository`.
- **Cause:** Unconfirmed; possibly sandbox-specific behavior of
  `git config --local` when writing a credential helper.
- **Mitigation:** Verify `git remote -v` after every `git config --local`
  operation. If empty, recover with:
  ```
  git remote add origin https://github.com/Uusintaja/shimtest2.git
  git branch --set-upstream-to=origin/main main
  ```

### PIT-equivalent 2 — `Author identity unknown`

- **Symptom:** `git commit` fails with `Author identity unknown` if no
  `user.name` / `user.email` is configured.
- **Mitigation:** Set local identity as in §5. Verify with
  `git config --local --get user.name`.

### PIT-equivalent 3 — Partial commit (cross-reference PIT-001)

- **Symptom:** `git add <file1> <file2>` only stages the named files; if
  the working tree has uncommitted modifications on other files, those
  are silently excluded from the commit.
- **Mitigation:** Use `git add -A` (or `git add .`) before commit. Verify
  with `git status --short` immediately before `git commit` to confirm no
  ` M` (unstaged modification) entries remain.

---

## 7. Security rules (always)

- **Mask the PAT in all output.** Never display the full PAT in chat,
  log lines, commit messages, or project files. Display only length +
  first 4 + last 4 characters.
- **Never commit the PAT.** Even though the credential file lives outside
  the repo, double-check before every `git add -A` that no PAT-like
  string is being staged.
- **Never write the PAT to working docs** (`ROADMAP.md`,
  `CODE_REVIEW_TODO.md`, `/drift_report.md`, or `/PITFALLS.md`).
- **Use branch protection as the safety boundary.** Do not push to
  branches outside the whitelist, even if the PAT would technically
  allow it.
- **Rotate the PAT regularly.** The user manages rotation; the assistant
  should flag approaching expiration if it becomes aware of it.

---

## 8. Cross-references

- General process pitfalls: see [`/PITFALLS.md`](../PITFALLS.md) at
  project root (per [`./DOCUMENTATION_POLICY.md`](./DOCUMENTATION_POLICY.md)
  §2.7).
- Drift between docs and source: see [`/drift_report.md`](../drift_report.md).
- Working-doc location convention: see
  [`./DOCUMENTATION_POLICY.md`](./DOCUMENTATION_POLICY.md) §2.6.
- Mode-string protocol: see [`./WORKFLOW_RULES.md`](./WORKFLOW_RULES.md) §1.
