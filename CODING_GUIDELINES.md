# Coding Guidelines

Baseline: post-rc hardening after `0.2.0-rc1`  
Current working version: `0.2.0-rc2-dev`

---

## 1. Time source policy

The project distinguishes two kinds of time values.

### 1.1 Wall-clock time

Use wall-clock time for human-readable absolute timestamps:

- wrapper log line prefix;
- `StartTime` / `EndTime` in result objects;
- release validation report timestamp;
- archive file timestamps;
- user-facing dates.

Allowed APIs:

```csharp
DateTime.Now
DateTime.UtcNow
DateTimeOffset.Now
```

PowerShell:

```powershell
Get-Date
```

### 1.2 Monotonic time

Use monotonic time for relative time and control-flow deadlines:

- latency metrics;
- elapsed duration metrics;
- timeout checks;
- Close/Shutdown budgets;
- output drain budgets;
- quiet period checks;
- retry/backoff deadlines.

Required API:

```csharp
Stopwatch.GetTimestamp()
Stopwatch.Frequency
```

Do not use `DateTime.Now` / `DateTime.UtcNow` differences for these values.

---

## 2. Timing helper pattern

CSharpHost should use helpers similar to:

```csharp
private static double ElapsedMs(long startTimestamp)
private static double ElapsedMs(long startTimestamp, long endTimestamp)
private static long DeadlineFromNowMs(int milliseconds)
private static string FmtMs(double milliseconds)
```

Formatting should use invariant culture so logs use dot decimal separators:

```text
1.234567
```

not locale-dependent comma separators.

---

## 3. Naming convention

Use names that expose time semantics.

Monotonic timestamp examples:

```csharp
signalPerfTicks
handlerEntryPerf
sendStartPerf
waitStartPerf
drainStartPerf
ctrlCDeadlinePerfTicks
```

Wall-clock examples:

```csharp
startTime
endTime
logTime
archiveTimestamp
```

Elapsed metric examples:

```csharp
sendLatencyMs
waitElapsedMs
drainElapsedMs
normalDrainDurationMs
```

Avoid ambiguous names such as:

```text
ticks
start
deadline
time
```

unless the surrounding scope makes the time source obvious.

---

## 4. Current accepted uses of DateTime

The following are intentionally still wall-clock based:

- `ResultState.Create(..., DateTime start)`;
- `ResultState.Complete(...)`;
- wrapper log line prefix;
- PowerShell post-action timing unless high precision is required later;
- archive file timestamp generation.

`DurationMs` in result JSON is a user-facing wall-clock lifecycle duration, not a benchmark metric.

---

## 5. Native resource rules

For unmanaged memory:

- initialize `IntPtr` to `IntPtr.Zero`;
- free in `finally` on partial failure;
- transfer ownership by setting local pointer back to `IntPtr.Zero` after successful return.

For handles:

- set handle fields to `IntPtr.Zero` immediately after closing;
- tolerate repeated cleanup;
- keep output pipe open long enough for reader drain when normal app exit is being processed.

---

## 6. Result state rules

C# internal result state should not rely on raw `Hashtable` mutation from multiple threads.

Current direction:

- use an internal thread-safe result abstraction;
- use atomic guards for single-shot operations such as sending ETX `0x03`;
- convert to PowerShell-friendly `Hashtable` only at the boundary.

---

## 7. Config rules

- Config reference must match `src/common.ps1` defaults and CSharpHost behavior.
- Reserved values must be rejected or clearly warned.
- Removed values must not appear as active config.
- Environment variable values are not logged by default.

---

## 8. Best-effort event rules

Close/Logoff/Shutdown paths must:

- avoid UI/window manipulation;
- avoid relying on PowerShell post-actions;
- use independent budgets;
- log minimally;
- use first terminal event wins semantics.
