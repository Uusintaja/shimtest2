<#
.SYNOPSIS
    Boundary tests for repeated same-process runs and parallel independent PowerShell process runs.

.DESCRIPTION
    These tests target wrapper lifecycle boundaries rather than app business behavior:

    1. Same PowerShell process, sequential wrapper invocations.
       Purpose: catch stale Add-Type/static/router state across repeated calls.

    2. Multiple independent PowerShell processes running wrappers in parallel.
       Purpose: validate that independent wrapper processes do not interfere with each other.

    This script intentionally does not test concurrent WrapperHost.Run calls inside the same
    PowerShell process. That scenario is unsupported by design. Use separate powershell.exe
    processes for concurrent wrappers.

.EXAMPLE
    .\scripts\test-boundary-runs.ps1

.EXAMPLE
    .\scripts\test-boundary-runs.ps1 -SequentialIterations 5 -ParallelCount 3 -SleepSeconds 2
#>

param(
    [int]$SequentialIterations = 3,
    [int]$ParallelCount = 2,
    [int]$SleepSeconds = 2
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WrapperPath = Join-Path $ProjectRoot "wrapper-csharphost.ps1"
$NoOutputSleepExe = Join-Path $ProjectRoot "bin\no_output_sleep.exe"
$BoundaryRoot = Join-Path $ProjectRoot "logs\boundary"
$ConfigRoot = Join-Path $BoundaryRoot "configs"

function New-BoundaryConfig {
    param(
        [Parameter(Mandatory=$true)] [string]$Name,
        [Parameter(Mandatory=$true)] [int]$SleepSeconds
    )

    $workRoot = Join-Path $BoundaryRoot "work\$Name"
    $logFile = Join-Path $BoundaryRoot "wrapper.$Name.log"
    $appLogFile = Join-Path $BoundaryRoot "app.$Name.output.log"
    $configPath = Join-Path $ConfigRoot "$Name.ps1"

    $content = @"
return @{
    AppPath = '$($NoOutputSleepExe.Replace("'", "''"))'
    AppArgs = @('$SleepSeconds')
    WorkingDirectory = '$($workRoot.Replace("'", "''"))'
    CreateDirectories = @('$($workRoot.Replace("'", "''"))', '$($BoundaryRoot.Replace("'", "''"))')
    LogFilePath = '$($logFile.Replace("'", "''"))'
    AppOutputLogFilePath = '$($appLogFile.Replace("'", "''"))'
    OutputEncoding = 'utf-8'
    StripAnsiSequences = `$true
    InputMode = 'None'
    EnableShutdownSentinel = `$true
    PostActions = @(
        @{ Name='exit code is zero'; Type='ExitCodeEquals'; ExpectedExitCode=0; TreatFailureAsError=`$true }
    )
}
"@

    Set-Content -LiteralPath $configPath -Value $content -Encoding UTF8
    return $configPath
}

function Read-ResultJson {
    param([Parameter(Mandatory=$true)] [string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Result JSON not found: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Assert-BoundaryResult {
    param(
        [Parameter(Mandatory=$true)] $Result,
        [Parameter(Mandatory=$true)] [string]$Name
    )

    if ($Result.Metadata.Implementation -ne "CSharpHost") {
        throw "[$Name] Expected Implementation=CSharpHost, actual=$($Result.Metadata.Implementation)"
    }
    if ($Result.AppState.State -ne "Exited") {
        throw "[$Name] Expected AppState.State=Exited, actual=$($Result.AppState.State)"
    }
    if ([int]$Result.AppState.ExitCode -ne 0) {
        throw "[$Name] Expected AppExitCode=0, actual=$($Result.AppState.ExitCode)"
    }
    if (@($Result.WrapperState.Errors).Count -ne 0) {
        throw "[$Name] Expected WrapperState.Errors.Count=0, actual=$(@($Result.WrapperState.Errors).Count)"
    }
    if (@($Result.PostActions.Errors).Count -ne 0) {
        throw "[$Name] Expected PostActions.Errors.Count=0, actual=$(@($Result.PostActions.Errors).Count)"
    }
}

if (-not (Test-Path -LiteralPath $WrapperPath -PathType Leaf)) {
    throw "wrapper-csharphost.ps1 not found: $WrapperPath"
}
if (-not (Test-Path -LiteralPath $NoOutputSleepExe -PathType Leaf)) {
    throw "Required test binary not found: $NoOutputSleepExe. Compile tests\no_output_sleep.c first."
}

New-Item -ItemType Directory -Force -Path $BoundaryRoot, $ConfigRoot | Out-Null

$summary = @()

Write-Host "=== Boundary Test 1: sequential same-PowerShell invocations ==="
for ($i = 1; $i -le $SequentialIterations; $i++) {
    $name = "sequential_$i"
    $configPath = New-BoundaryConfig -Name $name -SleepSeconds 1
    $jsonPath = Join-Path $BoundaryRoot "result.$name.json"

    & $WrapperPath -ConfigPath $configPath -JsonOutputPath $jsonPath -NoSummary
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "[$name] wrapper exit code $exitCode" }

    $result = Read-ResultJson -Path $jsonPath
    Assert-BoundaryResult -Result $result -Name $name
    $summary += [pscustomobject]@{ Test=$name; Mode="SequentialSameProcess"; Status="PASS"; Json=$jsonPath }
    Write-Host "[PASS] $name"
}

Write-Host "=== Boundary Test 2: parallel independent powershell.exe invocations ==="
$processes = @()
for ($i = 1; $i -le $ParallelCount; $i++) {
    $name = "parallel_$i"
    $configPath = New-BoundaryConfig -Name $name -SleepSeconds $SleepSeconds
    $jsonPath = Join-Path $BoundaryRoot "result.$name.json"
    $stdoutPath = Join-Path $BoundaryRoot "stdout.$name.log"
    $stderrPath = Join-Path $BoundaryRoot "stderr.$name.log"

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $WrapperPath,
        '-ConfigPath', $configPath,
        '-JsonOutputPath', $jsonPath,
        '-NoSummary'
    )

    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $processes += [pscustomobject]@{ Name=$name; Process=$p; Json=$jsonPath; Stdout=$stdoutPath; Stderr=$stderrPath }
}

foreach ($item in $processes) {
    [void]$item.Process.WaitForExit()
    try { $item.Process.Refresh() } catch {}

    $exitCode = $null
    try { $exitCode = $item.Process.ExitCode } catch {}

    # In some Windows PowerShell 5.1 hosts, Start-Process -PassThru can leave ExitCode null even
    # after WaitForExit/Refresh when stdout/stderr are redirected. Treat JSON result as the source
    # of truth if the process has exited and the result file exists.
    if ($null -ne $exitCode -and $exitCode -ne 0) {
        $stderr = if (Test-Path $item.Stderr) { Get-Content -LiteralPath $item.Stderr -Raw } else { "" }
        throw "[$($item.Name)] wrapper process exit code $exitCode. Stderr: $stderr"
    }
    if ($null -eq $exitCode -and -not (Test-Path -LiteralPath $item.Json -PathType Leaf)) {
        $stderr = if (Test-Path $item.Stderr) { Get-Content -LiteralPath $item.Stderr -Raw } else { "" }
        throw "[$($item.Name)] wrapper process exit code is unavailable and result JSON was not created. Stderr: $stderr"
    }

    $result = Read-ResultJson -Path $item.Json
    Assert-BoundaryResult -Result $result -Name $item.Name
    $summary += [pscustomobject]@{ Test=$item.Name; Mode="ParallelIndependentProcess"; Status="PASS"; Json=$item.Json; ExitCode=$exitCode }
    Write-Host "[PASS] $($item.Name)"
}

Write-Host "=== Boundary Test Summary ==="
$summary | Format-Table -AutoSize

exit 0
