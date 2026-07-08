# ConPTY Wrapper Implementation Roadmap

## Step 1 - Design v2
Status: Done
Output: docs/history/design_v2.md

## Step 2 - Shared config/result model
Status: Done
Output:
- configs/sample.stdown.ps1
- configs/sample.echo.ps1
- src/common.ps1
- src/validate-config.ps1

## Step 3 - Implementation A: PowerShell-main MVP
Status: Validated for stdown.c core path
Output:
- legacy\wrapper.ps1

Notes:
- Implements core ConPTY startup/output/Ctrl+C/post-actions.
- At this stage, Close and shutdown were intentionally postponed to the later lifecycle-signal step.
- 2026-06-17: patched PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE lpValue handling after first Windows test returned 0xC0000142.
- 2026-06-17: stdown.c test passed: realtime output, Ctrl+C forwarding, exit code, post-actions.
- 2026-06-17: added ANSI/VT stripping option for app output logs and captured output matching.
- 2026-06-17: patched ANSI stripping for Windows PowerShell 5.1 by replacing unsupported `` `e `` usage with [char]27; changed stdown regex to ASCII-only Ctrl\+C to avoid UTF-8-without-BOM mojibake.

## Step 4 - Implementation B: PowerShell + C# WrapperHost
Status: Validated / promoted to CSharpHost mainline
Output:
- wrapper-csharphost.ps1

Notes:
- Embedded C# compiled at runtime by Add-Type. No separate persistent exe required for this mode.
- Implements same stdown.c core path as legacy\wrapper.ps1; Close/Shutdown were postponed at that stage and later completed in CSharpHost.

## Step 5 - Test matrix
Status: Done
Output:
- tests/*.c
- docs/reference/TEST_PROGRAMS.md
- configs/sample.ignore_ctrlc.ps1
- configs/sample.bulk_output.ps1
- configs/sample.exit_code.ps1
- configs/sample.stderr_output.ps1
- configs/sample.no_output_sleep.ps1
- scripts/run-tests.ps1
- docs/release/comparison_report.md

Notes:
- Added debug-friendly -JsonOutputPath and -PauseOnExit to both wrappers.
- 2026-06-17: documented Unicode input limitations; updated echo_stdin.c to call SetConsoleCP(CP_UTF8) and enlarge input buffer.
- 2026-06-17: updated run-tests.ps1 to avoid automatically pausing nested wrappers during interactive runs; documented line-input literal-character behavior.
- 2026-06-17: fixed AppArgs joining by renaming Join-WrapperCommandLineArgs parameter away from PowerShell automatic variable $args; added raw AppArgs debug logging.
- 2026-06-17: fixed AppArgs retrieval by using hashtable index access instead of dot access; fixed PowerShellMain negative exit code hex formatting.
- 2026-06-17: added static SignalRouter queue draining, duplicate Ctrl+C guard logging, AppArgsLine logging, and console input buffer drain for interactive debug sessions.

## Step 6 - Comparison report
Status: Done
Output:
- docs/release/comparison_report.md

Notes:
- Both implementations pass the base test matrix.
- CSharpHost is recommended as mainline.
- PowerShellMain remains as reference/fallback.
- Unicode/raw input is deferred as a future input-subsystem enhancement.

## Step 7 - Close/Shutdown extension
Status: Done
Output:
- wrapper-csharphost.ps1 implements CTRL_CLOSE_EVENT best-effort path
- wrapper-csharphost.ps1 implements hidden-window WM_QUERYENDSESSION shutdown/logoff best-effort path
- wrapper-csharphost.ps1 calls SetProcessShutdownParameters with application first-shutdown priority
- docs/history/design_v2.md updated with Close/Shutdown post-processing tiers and timing notes

Validation:
- Ctrl+C, Close, Logoff, Shutdown/restart validated in VM with stdown/app.exe
- Close/Logoff timeout+kill validated with ignore_ctrlc.exe
- Unsafe close-window hiding was reverted

Notes:
- PowerShellMain remains reference/fallback and does not receive Close/Shutdown backport for now
- Normal-exit output drain works functionally in 0.1.18, but its design is marked for Step 8 refinement


## Step 8 - Output/Input subsystem refinement
Status: Phase 1 Done
Priority: High
Output:
- wrapper-csharphost.ps1 0.1.19 normal AppExited path closes HPCON after process exit, then drains output to EOF/queue-empty
- docs/history/design_v2.md documents normal output drain semantics
- comparison report records Step 8 phase 1 result

Validation:
- stdown Ctrl+C PASS
- bulk_output normal AppExited PASS
- bulk_output Ctrl+C wrapper-flow PASS
- bulk_output Close best-effort PASS

Notes:
- Unicode/raw input module is deferred.
- AppOutputLog remains auxiliary, but serialized drain/write and normal output drain improved its practical ordering in tests.

## Step 8.2 - Architecture review and cleanup
Status: In Progress
Priority: High
Output:
- docs/architecture/review.md

Planned remaining output:
- docs/reference/CONFIG_REFERENCE.md (done)
- sample.bulk_output.ctrlc.ps1 (done)
- sample.args_env.ps1 and tests/args_env.c (done)
- reserved/deprecated option cleanup notes
- logging semantics cleanup (done: 0.1.23 RunId + core/post-action phase markers)
- release-candidate stabilization recommendation


## Step 9 - RC preparation
Status: Done
Output:
- WrapperVersion bumped to 0.2.0-rc1
- configs/vaultwarden.template.ps1 added as production-like validation template
- CSharpHost namespace bumped to CSharpWrapperHost_v020rc1
- wrapper-csharphost.ps1 header cleaned
- README.md added
- docs/release/RELEASE_CHECKLIST.md added
- docs/release/ADVISORY_NOTES.md added for non-blocking final review risks
- scripts/validate-release.ps1 added for automated release validation/sign-off report

Notes:
- No core behavior changes in this step.
- CSharpHost is the recommended rc1 mainline.


## External review support
Status: Added
Output:
- docs\review_agents\DOC_REVIEW_AGENT.md

Purpose:
- Guide external doc/code review agents toward release-blocking and high-value issues.
- Prevent repeated low-value reports on accepted limitations.


## Documentation restructuring
Status: Done
Output:
- assistant\DOCUMENTATION_POLICY.md
- docs/architecture/architecture_0.2.0-rc1.md
- docs/history/design_v2_legacy.md
- docs/history/design_v2.md legacy notice

Purpose:
- Separate user docs, current developer architecture docs, working docs, and historical docs.
- Stop using legacy design_v2 as the current source of truth.


## Final rc1 sign-off
Status: Done
Output:
- docs/release/FINAL_SIGNOFF_0.2.0-rc1.md
- docs/architecture/architecture_0.2.0-rc1.md renamed from vague current.md

Decision:
- 0.2.0-rc1 is frozen as the current release-candidate baseline.
- No behavior changes should be made to rc1 unless a release-blocking defect is found.
- Future work must be post-rc development.


## Step 10 - Post-RC hardening
Status: In Progress
Current working version: 0.2.0-rc2-dev

Scope:
- Harden CSharpHost after frozen 0.2.0-rc1 baseline.
- Archive PowerShellMain reference implementation under legacy/.
- Fix input non-interactive handling, environment block safety, output line memory read, encoding utility duplication, and close fallback dead branch.
- Defer Hashtable/result state concurrency redesign to a dedicated follow-up discussion.

Note:
- 0.2.0-rc1 remains the frozen signed-off baseline.
- 0.2.0-rc2-dev is an active hardening working tree.


## Step 10.1 - Result state concurrency hardening
Status: In Progress - implementation completed, validation pending
Current working version: 0.2.0-rc2-dev

Implemented:
- Internal C# ResultState abstraction using ConcurrentDictionary and ConcurrentQueue.
- Atomic Ctrl+C send guard independent of result dictionary fields.
- TriggerReason first-wins semantics.
- PowerShell-facing result remains Hashtable.

Validation pending:
- stdown Ctrl+C
- repeated Ctrl+C / ignore_ctrlc
- Close path
- validate-release non-interactive matrix


## Step 10.2 - Time source policy hardening
Status: In Progress - implementation completed, validation pending
Current working version: 0.2.0-rc2-dev

Implemented:
- CSharpHost relative timing and control deadlines use Stopwatch-based monotonic timestamps.
- DateTime remains for wall-clock log timestamps and result StartTime/EndTime.
- CODING_GUIDELINES.md added with time source policy.

Validation pending:
- stdown Ctrl+C
- ignore_ctrlc Ctrl+C timeout
- stdown Close
- ignore_ctrlc Close
- validate-release non-interactive matrix

## Workflow support docs
Status: Done
Output:
- USER.md
- WORKFLOW_RULES.md
- docs/review_agents/DOC_REVIEW_AGENT.md
- docs/review_agents/CODE_REVIEW_AGENT.md

Purpose:
- Preserve user collaboration preferences.
- Preserve phase/loop execution rules.
- Move external agent review prompts out of project root.
- Reduce ambiguity during long-context work.


## Step 10.3 - Router instance architecture refactor
Status: In Progress - implementation completed, validation pending
Current working version: 0.2.0-rc2-dev

Implemented:
- ConsoleSignalRouter is now an instance router with a static process-level trampoline.
- ShutdownWindowRouter is now an instance lifecycle object with local hidden window ownership and Dispose/Join cleanup.
- PowerShellMain remains archived under legacy/.

Validation pending:
- validate-release non-interactive matrix
- stdown Ctrl+C
- repeated Ctrl+C / ignore_ctrlc
- stdown Close
- ignore_ctrlc Close
- Logoff/Shutdown VM if convenient


## Step 10.4 - Boundary lifecycle tests
Status: Added - validation pending
- Boundary test parallel ExitCode null handling fixed in test-boundary-runs.ps1
Output:
- scripts/test-boundary-runs.ps1

Purpose:
- Automate repeated same-PowerShell sequential wrapper invocations.
- Automate parallel independent powershell.exe wrapper invocations.
- Validate router instance architecture boundary behavior without manual timing tricks.


## Step 10.5 - Unsupported same-process concurrency negative test
Status: Added - validation pending
Output:
- scripts/test-unsupported-concurrent-run.ps1

Purpose:
- Prove that concurrent WrapperHost.Run calls inside the same PowerShell process fail safely with a clear structured error.
- Document the supported concurrency model: use separate powershell.exe processes for concurrent wrappers.


## Step 10.6 - Discussion target candidates
Status: Done
Output:
- discuss_target.md

Purpose:
- Rank next hardening directions before further execution.
- Provide a compact target list for comparison with other assistant proposals.
- Current recommended next discussion: Resource lifecycle hardening.


## Step 10.7 - Resource lifecycle hardening
Status: In Progress - implementation completed, validation pending
Current working version: 0.2.0-rc2-dev

Implemented:
- best-effort handler now forces run termination through finally even when exceptions occur.
- best-effort handler catch records errors and attempts safe kill when app is still alive.
- Ctrl+C timeout kill path now closes ConPTY for output completion and performs a short diagnostic drain.

Validation pending:
- validate-release
- ignore_ctrlc Ctrl+C timeout
- repeated Ctrl+C / ignore_ctrlc
- stdown Ctrl+C
- Close/Shutdown smoke checks if convenient


## Step 10.8 - Ctrl+C unresponsive policy
Status: In Progress - implementation completed, validation pending
Current working version: 0.2.0-rc2-dev

Implemented:
- Added CtrlCUnresponsivePolicy = Kill / Continue.
- Added CtrlCGracePeriodMs with policy-dependent defaults.
- Added CtrlCSentCount, CtrlCUnresponsiveCount, LastCtrlCSentAt result fields.
- LastCtrlCSentAt now records an ISO 8601 timestamp for sub-second audit clarity.
- Added tests/ctrlc_counter.c and configs/sample.ctrlc_counter.ps1.

Validation pending:
- compile ctrlc_counter.exe
- sample.ctrlc_counter.ps1 manual test
- validate-release


## Step 10.9 - RunRecord schema restructuring
Status: Done
Current working version: 0.2.0-rc2-dev

Implemented:
- Replaced flat result schema with RunRecord objects: Metadata, EventAudit, TerminalTrigger, AppState, WrapperState, PostActions.
- Removed active TriggerReason/FinalState/root AppExitCode/root WasKilled/root TimedOut schema.
- Kept StdoutBytes and OutputLines at root for future IO model work.

Validated:
- validate-release PASS
- stdown Ctrl+C PASS
- ignore_ctrlc Kill path PASS
- ctrlc_counter Continue path PASS
- Close regression PASS

Notes:
- JSON schema is accepted as successful.
- Cosmetic JSON formatter polish is deferred; do not continue spending core hardening time on it unless it blocks automation.
- Round 13 cleanup keeps JSON emission on PowerShell `ConvertTo-Json`; only unordered dictionary-to-ordered-object conversion is allowed before serialization.
- Round 13 cleanup also targets wrapper log prefix order, PowerShell config-path entry logging, shared CoreDurationMs timing helper usage, and human-readable RegexOutputContains messages.
