# Code Review Agent Guide

Baseline under review: post-rc hardening after `0.2.0-rc1`.  
Primary implementation: `wrapper-csharphost.ps1`.  
Archived reference implementation: `legacy\wrapper.ps1`.

---

## 1. Scope

Review `wrapper-csharphost.ps1`, `src/common.ps1`, `scripts/*.ps1`, and config files.

Do not require feature parity from `legacy\wrapper.ps1`; it is archived reference code.

---

## 2. High-priority code review targets

## 2.1 Severity definitions

Use these severity labels consistently:

| Severity | Meaning | Typical action |
|---|---|---|
| Critical | Likely data loss, process corruption, native resource corruption, or security-sensitive incorrect behavior in normal supported use. | Fix before next RC. |
| High | Real correctness or reliability bug in supported scenarios, especially signal/lifecycle/resource handling. | Fix in hardening phase unless explicitly deferred. |
| Medium | Plausible edge-case bug, portability issue, or maintainability risk with bounded impact. | Fix if low-risk, otherwise document/defer. |
| Low | Style, cleanup, rare corner case, or future-proofing. | Fix opportunistically. |
| Advisory | Deployment note or accepted limitation; not necessarily a defect. | Document or backlog. |

Do not inflate severity merely because a theoretical race exists. Tie severity to supported scenarios, likelihood, and impact.


Prioritize:

1. Native handle/resource lifecycle.
2. Thread safety and signal races.
3. ConPTY pipe ownership and output drain correctness.
4. Close/Logoff/Shutdown best-effort paths.
5. Config validation vs implementation behavior.
6. Add-Type/static state hazards.
7. Environment block creation and cleanup.
8. Error handling that can crash wrapper unexpectedly.

---

## 3. Accepted design constraints

Do not report these as bugs unless implementation contradicts documentation:

1. Close/Logoff/Shutdown are best-effort.
2. PowerShell PostActions are not guaranteed after best-effort system events.
3. `AppOutputLogFilePath` is auxiliary, not business-grade logging.
4. ConPTY output is a terminal stream and does not separate stdout/stderr.
5. Unicode/raw input and TUI behavior are out of scope for the current mainline.
6. `InputMode=Char`, `ContentMatcher`, and `CancelAndReissue` are reserved.

---

## 4. Classify findings

Use these categories:

- Correctness bug
- Hardening issue
- Maintainability issue
- Documentation/config mismatch
- Future feature
- Accepted limitation

For each finding include:

```text
ID
Category
Severity
File/location
Problem
Why it matters
Suggested fix
Release/hardening priority
```

---

## 5. Avoid low-value reports

Avoid focusing on:

1. code style only;
2. historical docs;
3. archived `legacy\wrapper.ps1` feature gaps;
4. known best-effort limitations;
5. app output log strictness in Close/Shutdown paths.
