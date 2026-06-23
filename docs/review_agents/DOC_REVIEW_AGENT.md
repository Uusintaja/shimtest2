# External Review Agent Guide

Purpose: guide external agents reviewing the ConPTY Generic Wrapper project so they focus on high-value issues instead of re-litigating known design tradeoffs.

Baseline: `0.2.0-rc1`  
Primary implementation: `wrapper-csharphost.ps1` / CSharpHost  
Reference implementation: `legacy\wrapper.ps1` / PowerShellMain

---

## 1. Project summary

This project is a Windows PowerShell 5.1 wrapper for line-oriented Windows console programs using ConPTY.

The mainline wrapper:

```text
wrapper-csharphost.ps1
```

uses embedded C# compiled by `Add-Type`. PowerShell handles config, post-actions, JSON/summary output, and user-facing script options. C# handles ConPTY, process lifecycle, IO pumping, signal routing, close/logoff/shutdown best-effort paths, and native resources.

The reference/fallback wrapper:

```text
legacy\wrapper.ps1
```

is not the production mainline and does not need full feature parity.

---

## 2. Highest-priority review goals

Focus on issues that could affect release-candidate correctness, deployment, or user understanding.

### P0 / Blocker

Report immediately if found:

1. Mainline CSharpHost cannot run or compile.
2. Required deployment files are missing or misnamed.
3. `WrapperVersion` / namespace / docs claim conflicting release identity.
4. Config reference contradicts actual CSharpHost behavior.
5. Documentation instructs users to rely on unsupported behavior.
6. Close/logoff/shutdown are described as guaranteed rather than best-effort.
7. Sensitive environment variable values are logged by default.
8. A sample config uses removed/dead config keys as if they still work.

### P1 / High

Important release-quality issues:

1. Docs disagree on primary implementation.
2. Docs imply `legacy\wrapper.ps1` is equivalent to `wrapper-csharphost.ps1`.
3. Docs confuse wrapper logs, wrapper-captured terminal output, and app-owned business logs.
4. Docs or configs confuse normal Ctrl+C path with Close/Shutdown best-effort paths.
5. Test instructions are impossible, unsafe, or misleading.
6. A config field is undocumented or documented with the wrong default.
7. A feature is marked supported but is actually reserved/experimental.
8. Markdown examples contain broken PowerShell syntax.

### P2 / Medium

Worth reporting, but not necessarily release-blocking:

1. Minor path separator inconsistency if it harms readability.
2. Historical docs mention old versions without enough context.
3. Missing cross-reference between related docs.
4. Naming inconsistencies that may confuse users.
5. Release checklist omissions.

### P3 / Low

Report only if grouped or easy to fix:

1. Typos.
2. Minor wording improvements.
3. Formatting inconsistencies that do not affect meaning.

---

## 3. Known accepted limitations

Do not report these as defects unless documentation contradicts them.

1. Close/logoff/shutdown are best-effort, not guaranteed.
2. PowerShell post-actions are not guaranteed after Close/Logoff/Shutdown.
3. `AppOutputLogFilePath` is auxiliary observability, not business-grade logging.
4. ConPTY combines stdout/stderr into a terminal stream.
5. Full TUI support is out of scope.
6. Unicode/IME/raw keyboard correctness is not guaranteed.
7. `InputMode=Char` is reserved/experimental.
8. `ShutdownMode=CancelAndReissue` is reserved and not implemented.
9. `ContentMatcher` is reserved and not implemented.
10. `legacy\wrapper.ps1` is reference/fallback; it does not need full CSharpHost parity.

---

## 4. Current validated behavior

The following should be treated as current baseline behavior:

1. Ctrl+C forwarding works through ConPTY ETX `0x03`.
2. Close sends ETX, waits a short independent budget, optionally kills, and logs minimally.
3. Logoff/shutdown/restart are handled through hidden-window `WM_QUERYENDSESSION` best-effort routing.
4. `SetProcessShutdownParameters` is verified in-process.
5. Normal AppExited path closes HPCON and drains remaining output before summary.
6. RunId separates appended log runs.
7. Environment override names are logged by default; values are not.
8. Stopwatch-based timing is used in CSharpHost timing logs.

---

## 5. Important terminology

Use these meanings when reviewing:

| Term | Meaning |
|---|---|
| wrapper lifecycle log | `LogFilePath`; wrapper's own operational log |
| app output log | `AppOutputLogFilePath`; wrapper-captured terminal output, auxiliary only |
| app business log | log written by the wrapped program itself |
| normal path | app exits naturally or after user Ctrl+C and PowerShell post-actions run |
| best-effort path | Close/logoff/shutdown, C# handler does minimal safety work; PowerShell may not resume |
| CSharpHost core | embedded C# native/ConPTY lifecycle |
| PowerShell post-actions | config-defined post-run checks/actions after C# returns |

---

## 6. Files to review

### Recommended full review input

Use the complete `shimtest2` project tree when possible, not only docs.

Minimum useful set:

```text
README.md
ROADMAP.md
wrapper-csharphost.ps1
src/common.ps1
docs/reference/CONFIG_REFERENCE.md
configs/*.ps1
docs/**/*.md
scripts/*.ps1
docs/reference/TEST_PROGRAMS.md
```

Why include code/configs?

Docs often look correct in isolation, but release problems usually occur at the boundary between:

```text
documentation <-> default config <-> sample config <-> implementation
```

Do not omit `tests/*.c`, `configs/vaultwarden.template.ps1`, or scripts when auditing deliverable existence. If a reduced review tree omits them, report the omission as a review-scope limitation rather than a project defect.

### Docs-only review

If only reviewing docs, include a file tree and clearly state that code/config consistency could not be fully verified.

---

## 7. Review method

For each issue, provide:

```text
ID
Severity: P0/P1/P2/P3
Files/locations
Problem
Why it matters
Recommended fix
Whether it is a release blocker
```

Prefer exact quotes and line references when possible.

Do not produce large lists of purely stylistic issues before reporting semantic contradictions.

---

## 8. Special checks

### 8.1 Version consistency

Check for:

```text
0.2.0-rc1
CSharpWrapperHost_v020rc1
```

Old `0.1.x` mentions are acceptable only when clearly historical.

### 8.2 Removed/dead config keys

These should not appear as active config:

```text
CloseTimeoutSeconds
ShutdownTimeoutSeconds
CloseHideWindowOnClose
```

Historical discussion is acceptable if clearly marked as historical/removed.

### 8.3 Reserved features

These may appear, but must be clearly marked reserved/experimental:

```text
InputMode=Char
ShutdownMode=CancelAndReissue
ContentMatcher
```

### 8.4 Best-effort wording

Close/logoff/shutdown docs must not imply:

```text
PostActions guaranteed
JSON guaranteed
PowerShell finally guaranteed
business cleanup guaranteed by OS
```

### 8.5 Environment variable safety

Docs/config should preserve:

```powershell
LogEnvironmentVariableValues = $false
```

unless explicitly discussing safe debugging.

### 8.6 Path examples

Examples should be valid PowerShell and not contain accidental escape/control characters.

---

## 9. What not to over-focus on

Avoid spending much effort on:

1. Historical bug chronology unless it creates current confusion.
2. Perfect path separator style if examples are clear and valid.
3. AppOutputLog strict completeness in Close/Shutdown paths.
4. PowerShellMain not having CSharpHost-only features.
5. Unicode/raw input implementation details unless docs overpromise support.

---

## 10. Output format example

```markdown
## Issue P1-003: Dead config key still documented as active

Severity: P1
Files:
- docs/history/design_v2.md §3
- src/common.ps1

Problem:
`CloseTimeoutSeconds` is described as active, but CSharpHost uses `CloseAppWaitMilliseconds`.

Why it matters:
Users may configure `CloseTimeoutSeconds` and see no effect.

Recommended fix:
Remove it from active config docs or mark it historical/removed.

Release blocker: Yes, if present in CONFIG_REFERENCE or sample configs.
```
