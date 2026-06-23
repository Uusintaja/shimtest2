# Advisory Notes - 0.2.0-rc1

These notes record non-blocking risks from the final external review. They are not release blockers for the current CSharpHost rc1 baseline, but they should be considered when deploying to unusual environments or planning post-rc work.

---

## 1. Add-Type static state

`Add-Type` loads embedded C# types into the current PowerShell process and cannot unload them. CSharpHost uses a versioned namespace such as:

```text
CSharpWrapperHost_v020rc1
```

and resets signal queues on registration. This is sufficient for rc1 testing. If future code adds more static state, it must be explicitly reset at the start/end of each run.

Recommendation:

- Start a new PowerShell process when validating embedded C# changes.
- Keep namespace versioning while using embedded `Add-Type`.

---

## 2. Windows Forms dependency

CSharpHost uses `System.Windows.Forms.NativeWindow` and `Application.Run()` for the hidden shutdown/logoff sentinel window.

Expected environment:

```text
Windows 10/11 desktop class systems
Windows PowerShell 5.1
.NET Framework with System.Windows.Forms.dll
```

This may not work on stripped-down environments such as Windows Server Core, Nano Server, WinPE, or constrained PowerShell hosts.

Recommendation:

- Treat desktop Windows 10/11 as the supported rc1 deployment target.
- If deploying to Server Core-like environments, test `Add-Type` and `ShutdownWindowRouter` explicitly.

---

## 3. Timing metric precision

CSharpHost uses high-resolution `Stopwatch` for short send-latency intervals. Some longer or cross-thread metrics still use wall-clock timestamps or mixed timing sources.

Therefore values such as:

```text
signalQueueLatencyMs
appExitAfterCtrlCSentMs
```

should be read as operational diagnostics, not precise benchmark measurements.

Recommendation:

- Use timing values for relative tuning and gross latency analysis.
- Do not treat them as formal performance benchmarks.

---

## 4. Test program source review

The test programs under `tests/*.c` exist for wrapper validation. They are not security-audited production programs.

Recommendation:

- For release validation, compile and run them as documented.
- For security-sensitive deployment, review any custom app source separately.

---

## 5. ConPTY size

The current CSharpHost creates the pseudo console with a fixed size:

```text
120 x 30
```

This is acceptable for the line-oriented programs targeted by rc1. Programs that query console dimensions may observe this fixed size.

Recommendation:

- Do not use rc1 for programs requiring precise terminal resizing or full TUI behavior.
- Consider configurable ConPTY size in a future release if needed.

---

## 6. PowerShell and process bitness

Embedded C# runs in the bitness of the hosting PowerShell process. A 64-bit PowerShell wrapping a 32-bit program is generally fine for line-oriented use, but filesystem redirection and environment differences can matter for some apps.

Recommendation:

- Use the PowerShell bitness appropriate for your deployment.
- Validate paths involving `System32`, `SysWOW64`, registry views, or native DLL loading.

---

## 7. Environment value coercion

User config values in `EnvironmentVariables` should be strings. The standard config path casts values to strings during merge, but custom script paths that bypass common helpers may behave differently.

Recommendation:

```powershell
EnvironmentVariables = @{
    ENV_FILE = [string]$EnvFilePath
}
```

Avoid nested objects or complex PowerShell objects as environment values.

---

## 8. Shutdown sentinel disabled

If:

```powershell
EnableShutdownSentinel = $false
```

then hidden-window `WM_QUERYENDSESSION` handling is disabled. The wrapper may still receive some console events, but shutdown/logoff best-effort behavior should not be expected.

Recommendation:

- Keep `EnableShutdownSentinel = $true` for production-like desktop deployments.
- Only disable it intentionally when shutdown/logoff handling is not desired.

---

## 9. Output reader error exposure

If the output reader throws, CSharpHost may enqueue a message like:

```text
[wrapper-reader-error] <message>
```

This can appear in host console and app output log.

Recommendation:

- Treat this as diagnostic output.
- Avoid placing secrets in file paths/configuration where possible.
- For stricter environments, consider a future option to route reader errors only to wrapper lifecycle logs.

---

## 10. Release-version bump is manual

Version and namespace changes currently require editing multiple files. `validate-release.ps1` detects inconsistencies but does not update them.

Recommendation:

- Use `validate-release.ps1` after any version bump.
- Consider a future `bump-version.ps1` helper if release cadence increases.
