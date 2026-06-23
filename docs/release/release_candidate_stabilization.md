# Release Candidate Stabilization Recommendation

Date: 2026-06-19  
Baseline version: 0.2.0-rc1  
Current tag: 0.2.0-rc1  
Primary implementation: `wrapper-csharphost.ps1` / CSharpHost

---

## 1. Recommendation

The project is ready to freeze feature development and enter a release-candidate stabilization phase.

Current baseline:

```text
0.2.0-rc1
```

Do not add Unicode/raw input, TUI support, new UX behavior, or additional shutdown modes before this stabilization pass completes.

---

## 2. Why CSharpHost is the release candidate mainline

CSharpHost has validated support for:

| Capability | Status |
|---|---|
| ConPTY startup | PASS |
| AppArgs injection | PASS |
| Environment override/inheritance | PASS |
| Realtime terminal output | PASS |
| Normal output drain | PASS |
| Ctrl+C forwarding | PASS |
| Ctrl+C ignored -> timeout kill | PASS |
| Console close best-effort | PASS |
| Logoff/shutdown/restart best-effort | PASS in VM |
| PostActions | PASS |
| JSON output | PASS |
| RunId log separation | PASS |
| Stopwatch timing | PASS |

PowerShellMain remains a reference/fallback implementation and should not block CSharpHost release-candidate work.

---

## 3. Validated test set

### 3.1 Functional tests

| Test | Result | Notes |
|---|---|---|
| `stdown Ctrl+C` | PASS | app receives Ctrl+C and writes `done`. |
| `stdown Close` | PASS | best-effort close writes `done`. |
| `stdown Logoff/Shutdown` | PASS | hidden-window path validated in VM. |
| `ignore_ctrlc Ctrl+C` | PASS | timeout + kill. |
| `ignore_ctrlc Close/Logoff` | PASS | timeout + kill. |
| `bulk_output normal` | PASS | summary after `bulk-line:19999`. |
| `bulk_output Ctrl+C` | PASS with ctrlc-specific config | default `0xC000013A` expected. |
| `stderr_output` | PASS | stdout/stderr visible in ConPTY terminal stream. |
| `no_output_sleep` | PASS | no-output app waits naturally. |
| `echo_stdin basic` | PASS | basic line input. |
| `args_env` | PASS | multi-args and env override/inheritance. |

### 3.2 Observability tests

| Item | Result |
|---|---|
| RunId separation | PASS |
| PowerShell entry/core/post-action phase logs | PASS |
| Environment override names logged without values | PASS |
| Stopwatch timing format | PASS |
| Shutdown priority set/get verification | PASS |

---

## 4. Known limitations for rc1

These are accepted limitations, not release blockers:

1. `InputMode=Line` is not a raw keyboard/IME/TUI solution.
2. `InputMode=Char` is reserved/experimental.
3. Complex Unicode, surrogate pairs, combining marks, and IME input are not guaranteed.
4. `AppOutputLogFilePath` is auxiliary observability, not a business-grade log.
5. stdout/stderr are not separated in ConPTY mode.
6. Close/logoff/shutdown are best-effort by OS nature.
7. PowerShellMain does not have full Close/Shutdown parity.
8. `ShutdownMode=CancelAndReissue` is reserved and not implemented.
9. `ContentMatcher` is reserved and not implemented.

---

## 5. Cleanup completed before rc1

### 5.1 Version naming

Completed:

```text
WrapperVersion = 0.2.0-rc1
CSharp namespace = CSharpWrapperHost_v020rc1
```

Namespace versioning remains in use while using embedded `Add-Type`.

### 5.2 Header comments

Completed for `wrapper-csharphost.ps1`: the script is now identified as the release-candidate CSharpHost mainline.

### 5.3 Config comments

Sample configs have been updated for the rc1 behavior. Continue to avoid stale comments that imply lifecycle-signal handling is still pending.

### 5.4 Documentation index

Completed: top-level `README.md` points to:

```text
README.md
docs/reference/CONFIG_REFERENCE.md
docs/history/design_v2.md
docs/release/comparison_report.md
docs/architecture/review.md
docs/release/release_candidate_stabilization.md
docs/release/RELEASE_CHECKLIST.md
docs/release/ADVISORY_NOTES.md
scripts/validate-release.ps1
ROADMAP.md
```

### 5.5 Test command summary

Document the minimal rc1 validation commands:

```powershell
.\scripts\run-tests.ps1 -Implementation CSharpHost
.\scripts\run-tests.ps1 -Implementation CSharpHost -IncludeInteractive
```

Manual VM tests:

```text
stdown close
stdown logoff
stdown shutdown/restart
ignore_ctrlc close/logoff
```

---

## 6. Post-rc1 priorities

After rc1 stabilizes, consider these in order:

1. Output pump state-machine refactor, if maintainability becomes painful.
2. High-resolution timing cleanup for PowerShell-side post-actions if needed.
3. Unicode/raw input module design.
4. Optional precompiled C# host packaging.
5. Optional content matcher / auto-response module.
6. Optional stdout/stderr separated non-ConPTY mode.

---

## 7. Final recommendation

RC1 preparation is complete. Do not add new feature development until final rc validation is complete.

The remaining work is validation and packaging discipline:

1. run final CSharpHost validation matrix;
2. run manual Close/Logoff/Shutdown checks if needed;
3. freeze current behavior as `0.2.0-rc1`;
4. document any rc validation findings without adding new features.


## 8. Production-like validation: vaultwarden

A self-compiled Windows `vaultwarden.exe` was used as a production-like validation target.

Validated results:

- `ENV_FILE` override works.
- `WorkingDirectory = VaultCore` works with adjacent `web-vault`.
- Ctrl+C graceful exit works.
- Close best-effort graceful exit works.
- Logoff/shutdown/restart best-effort graceful exit works in VM.
- SQLite data remained usable after logoff/shutdown tests.
- Timing metrics were useful for tuning config budgets.

A template config is provided:

```text
configs/vaultwarden.template.ps1
```

Important conclusion:

- vaultwarden's own logs and wrapper logs must be treated separately.
- `AppOutputLogFilePath` is wrapper-captured terminal output, not vaultwarden's authoritative log.
- vaultwarden log archive is implemented only as a normal-path PostAction in the template.
- Close/Shutdown PostActions are not guaranteed and should not be relied upon for critical archive/cleanup.
