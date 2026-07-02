# Code Review Todo

Current phase: post-rc hardening (`0.2.0-rc2-dev`).

---

## Active discussion

Router instance architecture refactor executed. Awaiting user validation.

---

## Approved for next execution

None until validation feedback arrives.

---

## Deferred

### Remaining first hardening batch

Deferred until after current execution/testing:

- Console input unavailable downgrade deeper testing.
- Environment null-removal behavior verification.
- BuildEnvironmentBlock resource safety verification.
- Output drain CPU-yield hardening.
- ShutdownWindowRouter lifecycle hardening.
- Dispose/reader coordination hardening.

### ResultState follow-up

Implemented first pass, but deferred for later discussion if needed:

- Stronger multi-field terminal-state transaction model.
- FinalState priority rules.
- Full state-machine style result transitions.

### Additional code review report items

Pending triage after current validation:

- SignalRouter.Register handler gap.
- SendCtrlC after `ClosePseudoConsoleForOutputCompletion`.
- ShutdownWindowRouter lifecycle races.
- Dispose/read thread coordination.
- SignalRouter static field memory barriers.
- Timeout/kill output drain path.
- Startup PowerShell try/catch and diagnostics.

---

## Done

- Ctrl+C unresponsive policy implemented: Kill/Continue, grace period config, ctrlc_counter test fixture.
- Best-effort exception completion guarantee implemented: handler catch records error, attempts safe kill, and finally forces `running=false`.
- Ctrl+C timeout kill path now performs diagnostic output drain with internal 1000ms/100ms budget.
- discuss_target.md created with top three next hardening directions and candidate issues.
- Unsupported same-process concurrency negative test script added: scripts\test-unsupported-concurrent-run.ps1.
- Boundary test parallel ExitCode null handling fixed; JSON result is used as source of truth if Process.ExitCode is unavailable.
- Boundary lifecycle test script added: scripts\test-boundary-runs.ps1.
- Router instance architecture refactor implemented: ConsoleSignalRouter instance with static trampoline, ShutdownWindowRouter instance lifecycle.
- USER.md wording clarified: README is for end users/operators.
- Workflow support docs reorganized: USER.md, WORKFLOW_RULES.md, review agent docs moved under docs\review_agents.
- `CODE_REVIEW_AGENT.md` created.
- PowerShellMain archived under `legacy\wrapper.ps1`.
- `ResultState` concurrency redesign implemented for CSharpHost internals.
- `DOCUMENTATION_POLICY.md` control-character issue fixed.
- Best-effort wait logs now include `exitCode=...`.
- Best-effort path now logs when ETX is not sent because Ctrl+C was already sent earlier.

---

## Rejected / accepted risk

None yet.

---

## Operating rules

This file is a temporary working document for code review and hardening loops.

Rules:

1. At the start of each discussion phase, clear or move resolved items out of active sections.
2. Keep unresolved items visible so they can be picked up in the next discussion.
3. At the end of each discussion phase, record what is approved for the next execution phase.
4. At the start of each execution phase, read this file before modifying code.
5. At the end of each execution phase, update status: done, deferred, rejected, or still active.
6. This file may be edited in both discussion and execution phases, similar to `ROADMAP.md`.
