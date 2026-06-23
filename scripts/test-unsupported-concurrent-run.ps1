<#
.SYNOPSIS
    Negative boundary test: concurrent WrapperHost.Run calls in the same PowerShell process are unsupported.

.DESCRIPTION
    This script loads the embedded CSharpHost type from wrapper-csharphost.ps1 without running the
    wrapper script entrypoint. It then starts one WrapperHost.Run call in a background runspace and
    attempts a second WrapperHost.Run call in the same PowerShell process.

    Expected behavior:
      - first run succeeds;
      - second run is rejected with a clear structured error mentioning concurrent Run calls;
      - this proves the unsupported same-process concurrency path fails safely instead of producing
        undefined shared static state behavior.

    This is a negative test and is intentionally not part of the default validation matrix.
#>

param(
    [int]$SleepSeconds = 4
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WrapperPath = Join-Path $ProjectRoot "wrapper-csharphost.ps1"
$CommonPath = Join-Path $ProjectRoot "src\common.ps1"
$NoOutputSleepExe = Join-Path $ProjectRoot "bin\no_output_sleep.exe"
$BoundaryRoot = Join-Path $ProjectRoot "logs\boundary_concurrent"

function Import-CSharpHostTypeFromWrapper {
    param([Parameter(Mandatory=$true)] [string]$WrapperPath)

    $text = Get-Content -LiteralPath $WrapperPath -Raw
    $match = [regex]::Match($text, '(?s)function\s+Add-CSharpHostType\s*\{.*?\n\}\s*\n\s*\$userConfig\s*=')
    if (-not $match.Success) {
        throw "Could not extract Add-CSharpHostType from wrapper-csharphost.ps1"
    }

    $functionText = $match.Value -replace '\n\s*\$userConfig\s*=\s*$', "`n"
    Invoke-Expression $functionText
    Add-CSharpHostType

    $nsMatch = [regex]::Match($text, 'namespace\s+(CSharpWrapperHost_[A-Za-z0-9]+)')
    if (-not $nsMatch.Success) {
        throw "Could not find CSharpHost namespace in wrapper-csharphost.ps1"
    }
    return $nsMatch.Groups[1].Value
}

function New-ConcurrentRunConfig {
    param(
        [Parameter(Mandatory=$true)] [string]$Name,
        [Parameter(Mandatory=$true)] [int]$SleepSeconds
    )

    $workRoot = Join-Path $BoundaryRoot "work\$Name"
    $logFile = Join-Path $BoundaryRoot "wrapper.$Name.log"
    $appLogFile = Join-Path $BoundaryRoot "app.$Name.output.log"
    New-Item -ItemType Directory -Force -Path $workRoot, $BoundaryRoot | Out-Null

    $config = New-WrapperDefaultConfig
    $config["RunId"] = "unsupported-concurrent-$Name"
    $config["AppPath"] = $NoOutputSleepExe
    $config["AppArgs"] = @([string]$SleepSeconds)
    $config["WorkingDirectory"] = $workRoot
    $config["EnvironmentVariables"] = @{}
    $config["CreateDirectories"] = @($workRoot, $BoundaryRoot)
    $config["LogFilePath"] = $logFile
    $config["AppOutputLogFilePath"] = $appLogFile
    $config["InputMode"] = "None"
    $config["EnableShutdownSentinel"] = $true
    return $config
}

function Invoke-WrapperHostRunByReflection {
    param(
        [Parameter(Mandatory=$true)] [string]$TypeName,
        [Parameter(Mandatory=$true)] [hashtable]$Config
    )

    $type = $TypeName -as [type]
    if ($null -eq $type) { throw "Type not found: $TypeName" }
    $method = $type.GetMethod("Run")
    if ($null -eq $method) { throw "Run method not found on $TypeName" }
    return $method.Invoke($null, @([System.Collections.IDictionary]$Config, ""))
}

. $CommonPath

if (-not (Test-Path -LiteralPath $NoOutputSleepExe -PathType Leaf)) {
    throw "Required test binary not found: $NoOutputSleepExe. Compile tests\no_output_sleep.c first."
}

$namespace = Import-CSharpHostTypeFromWrapper -WrapperPath $WrapperPath
$typeName = "$namespace.WrapperHost"
Write-Host "Loaded CSharpHost type: $typeName"

$config1 = New-ConcurrentRunConfig -Name "first" -SleepSeconds $SleepSeconds
$config2 = New-ConcurrentRunConfig -Name "second" -SleepSeconds $SleepSeconds

# First run in a background runspace inside the same PowerShell process.
$ps = [PowerShell]::Create()
[void]$ps.AddScript({
    param($TypeName, $Config)
    $type = $TypeName -as [type]
    $method = $type.GetMethod("Run")
    return $method.Invoke($null, @([System.Collections.IDictionary]$Config, ""))
}).AddArgument($typeName).AddArgument($config1)

$async = $ps.BeginInvoke()
Start-Sleep -Milliseconds 750

# Second run in the same process should be rejected by ConsoleSignalRouter.Register.
$secondResult = Invoke-WrapperHostRunByReflection -TypeName $typeName -Config $config2

# Wait for first to complete.
$firstCollection = $ps.EndInvoke($async)
$ps.Dispose()
$firstResult = @($firstCollection)[0]

$secondErrors = @($secondResult.Errors)
$secondErrorText = ($secondErrors -join "`n")

$firstOk = ($firstResult.FinalState -eq "Exited" -and [int]$firstResult.AppExitCode -eq 0 -and @($firstResult.Errors).Count -eq 0)
$secondRejected = ($secondResult.FinalState -eq "Error" -and $secondErrorText -match "Concurrent WrapperHost\.Run calls")

Write-Host "=== Unsupported concurrent Run test summary ==="
Write-Host "First run    : FinalState=$($firstResult.FinalState), AppExitCode=$($firstResult.AppExitCode), Errors=$(@($firstResult.Errors).Count)"
Write-Host "Second run   : FinalState=$($secondResult.FinalState), Errors=$(@($secondResult.Errors).Count)"
Write-Host "Rejected msg : $($secondErrorText -replace "`r?`n", " | ")"

if (-not $firstOk) {
    throw "First run did not complete successfully."
}
if (-not $secondRejected) {
    throw "Second same-process concurrent run was not rejected with the expected structured error."
}

Write-Host "[PASS] Same-process concurrent WrapperHost.Run is rejected safely."
exit 0
