# Final Sign-off - ConPTY Wrapper 0.2.0-rc1

Date: 2026-06-20  
Version: 0.2.0-rc1  
Primary implementation: `wrapper-csharphost.ps1` / CSharpHost  
Status: Frozen release-candidate baseline

---

## 1. Final decision

`0.2.0-rc1` is accepted as the current release-candidate baseline.

No further behavior changes should be made to rc1 unless a release-blocking defect is found.

---

## 2. Validation summary

| Area | Result | Notes |
|---|---:|---|
| Automated release validation | PASS | `validate-release.ps1` passed. |
| Non-interactive CSharpHost matrix | PASS | All tests passed. |
| Ctrl+C interactive behavior | PASS | Validated with stdown and production-like app. |
| Console Close behavior | PASS | Best-effort path validated. |
| Logoff/Shutdown behavior | PASS | Validated in VM and real-machine scenarios where applicable. |
| Production-like validation | PASS | Validated with self-compiled Windows `vaultwarden.exe`. |
| Documentation human review | PASS | Documentation structure reviewed and reorganized. |
| External P0/P1 review | PASS | No blocker/high-priority findings remain. |

---

## 3. Accepted limitations

The following are accepted for rc1 and are not release blockers:

1. Close/logoff/shutdown are best-effort and not OS-guaranteed.
2. PowerShell PostActions are not guaranteed after Close/Logoff/Shutdown.
3. `AppOutputLogFilePath` is auxiliary observability, not business-grade logging.
4. ConPTY mode does not provide strict stdout/stderr separation.
5. Full TUI behavior is out of scope.
6. Unicode/IME/raw keyboard input is not guaranteed.
7. `InputMode=Char` is reserved/experimental and rejected in rc1.
8. `ShutdownMode=CancelAndReissue` is reserved and rejected in rc1.
9. `ContentMatcher` is reserved and not implemented.
10. `legacy\wrapper.ps1` is reference/fallback and is not feature-equivalent to CSharpHost.

See also:

```text
docs\release\ADVISORY_NOTES.md
```

---

## 4. Frozen mainline

Use:

```text
wrapper-csharphost.ps1
```

Do not treat `legacy\wrapper.ps1` as the primary release line.

---

## 5. Required files for minimal deployment

```text
wrapper-csharphost.ps1
src\common.ps1
configs\<app>.ps1
bin\<app>.exe
```

Recommended docs:

```text
README.md
docs\reference\CONFIG_REFERENCE.md
docs\release\RELEASE_CHECKLIST.md
docs\release\ADVISORY_NOTES.md
```

---

## 6. Next work after rc1

Future work must be treated as post-rc development and should not be mixed into this frozen baseline.

Potential post-rc directions:

1. Unicode/raw input module.
2. Output pump state-machine refactor if maintainability requires it.
3. Optional precompiled C# host packaging.
4. Optional content matcher / auto-response module.
5. Optional stdout/stderr separated non-ConPTY mode.
6. Optional log rotation for wrapper logs.

---

## 7. Sign-off

Manual checks: PASS  
Advisory risks accepted: PASS  
Release-candidate baseline frozen: PASS
