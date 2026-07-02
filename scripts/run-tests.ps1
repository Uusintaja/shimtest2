<#
.SYNOPSIS
    Semi-automatic test runner for wrapper implementations.

.DESCRIPTION
    Runs non-interactive tests automatically. Interactive tests requiring Ctrl+C or user input are
    listed with commands but not run unless -IncludeInteractive is specified.

.EXAMPLE
    .\scripts\run-tests.ps1 -Implementation CSharpHost
    .\scripts\run-tests.ps1 -Implementation PowerShellMain
#>

param(
    [ValidateSet("CSharpHost", "PowerShellMain", "Both")]
    [string]$Implementation = "CSharpHost",

    [switch]$IncludeInteractive,

    [switch]$PauseOnEach
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $ProjectRoot "src\common.ps1")
$LogRoot = Join-Path $ProjectRoot "logs"
if (-not (Test-Path -LiteralPath $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }

$impls = if ($Implementation -eq "Both") { @("CSharpHost", "PowerShellMain") } else { @($Implementation) }

$tests = @(
    @{ Name="bulk_output"; Config="configs\sample.bulk_output.ps1"; Interactive=$false; Notes="Large output drain" },
    @{ Name="exit_code"; Config="configs\sample.exit_code.ps1"; Interactive=$false; Notes="Argument and exit-code propagation" },
    @{ Name="stderr_output"; Config="configs\sample.stderr_output.ps1"; Interactive=$false; Notes="stdout/stderr combined ConPTY stream" },
    @{ Name="no_output_sleep"; Config="configs\sample.no_output_sleep.ps1"; Interactive=$false; Notes="No-output process should not be killed" },
    @{ Name="args_env"; Config="configs\sample.args_env.ps1"; Interactive=$false; Notes="Argument and environment override/inheritance test" },
    @{ Name="stdown"; Config="configs\sample.stdown.ps1"; Interactive=$true; Notes="Press Ctrl+C after several counter lines" },
    @{ Name="ignore_ctrlc"; Config="configs\sample.ignore_ctrlc.ps1"; Interactive=$true; Notes="Press Ctrl+C; app ignores it; wrapper should kill after timeout" },
    @{ Name="ctrlc_counter"; Config="configs\sample.ctrlc_counter.ps1"; Interactive=$true; Notes="Press Ctrl+C three times, waiting slightly more than 500ms between presses; app exits on third signal" },
    @{ Name="echo"; Config="configs\sample.echo.ps1"; Interactive=$true; Notes="Type some text, then quit" },
    @{ Name="bulk_output_ctrlc"; Config="configs\sample.bulk_output.ctrlc.ps1"; Interactive=$true; Notes="Press Ctrl+C during bulk output; default app exit 0xC000013A is expected" }
)

$summary = @()
foreach ($impl in $impls) {
    $script = if ($impl -eq "CSharpHost") { "wrapper-csharphost.ps1" } else { "wrapper.ps1" }
    foreach ($t in $tests) {
        if ($t.Interactive -and -not $IncludeInteractive) {
            Write-Host "[SKIP][interactive] $impl/$($t.Name): $($t.Notes)"
            continue
        }

        $configPath = Join-Path $ProjectRoot $t.Config
        $jsonPath = Join-Path $LogRoot ("result.{0}.{1}.json" -f $impl.ToLowerInvariant(), $t.Name)
        $scriptPath = Join-Path $ProjectRoot $script
        Write-Host "[RUN] $impl/$($t.Name) - $($t.Notes)"
        if ($t.Interactive) {
            Write-Host "      Interactive instruction: $($t.Notes)" -ForegroundColor Yellow
            if (-not $PauseOnEach) { Write-Host "      Note: wrapper pause is disabled inside run-tests; next test starts immediately after result." -ForegroundColor DarkYellow }
        }

        # Do not automatically pass -PauseOnExit for interactive tests. If the nested wrapper pauses
        # and the user presses Ctrl+C at its Read-Host prompt, the Ctrl+C can abort this test runner
        # because script invocation happens inside the same PowerShell process. Keep pauses controlled
        # by -PauseOnEach only.
        Clear-WrapperConsoleInputBuffer
        & $scriptPath -ConfigPath $configPath -JsonOutputPath $jsonPath -NoSummary:(!$t.Interactive) -PauseOnExit:$PauseOnEach
        $exit = $LASTEXITCODE
        Clear-WrapperConsoleInputBuffer
        $status = if ($exit -eq 0) { "PASS" } else { "FAIL(exit=$exit)" }
        $summary += [pscustomobject]@{ Implementation=$impl; Test=$t.Name; Status=$status; Json=$jsonPath }
        Write-Host "[$status] $impl/$($t.Name)"
    }
}

Write-Host "=== Test Summary ==="
$summary | Format-Table -AutoSize
