<#
.SYNOPSIS
    Automated release validation/sign-off helper for the ConPTY wrapper.

.DESCRIPTION
    Performs automated checks that are safe to run without human interaction:
      - required file presence
      - version/namespace consistency
      - PowerShell and OS environment capture
      - basic stale-text scan
      - optional non-interactive CSharpHost test matrix
      - optional Markdown report generation

    This script does not replace manual Ctrl+C / Close / Logoff / Shutdown validation.

.EXAMPLE
    .\scripts\validate-release.ps1 -ExpectedVersion "0.2.0-rc1" -RunNonInteractiveTests -GenerateMarkdownReport
#>

param(
    [string]$ExpectedVersion = "0.2.0-rc2-dev",
    [switch]$RunNonInteractiveTests,
    [switch]$GenerateMarkdownReport
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LogRoot = Join-Path $ProjectRoot "logs"
if (-not (Test-Path -LiteralPath $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportJsonPath = Join-Path $LogRoot "release_validation_$timestamp.json"
$reportMdPath = Join-Path $LogRoot "release_validation_$timestamp.md"

function New-CheckResult {
    param(
        [string]$Name,
        [bool]$Pass,
        [string]$Message,
        [string]$Severity = "Error"
    )
    [pscustomobject]@{
        Name = $Name
        Pass = $Pass
        Severity = $Severity
        Message = $Message
    }
}

function Test-FileExistsCheck {
    param([string]$RelativePath, [string]$Severity = "Error")
    $path = Join-Path $ProjectRoot $RelativePath
    if (Test-Path -LiteralPath $path) {
        return New-CheckResult -Name "File exists: $RelativePath" -Pass $true -Message "Found: $RelativePath" -Severity $Severity
    }
    return New-CheckResult -Name "File exists: $RelativePath" -Pass $false -Message "Missing: $RelativePath" -Severity $Severity
}

$checks = New-Object System.Collections.Generic.List[object]

# 1. Required file checks
$requiredFiles = @(
    "wrapper-csharphost.ps1",
    "src\common.ps1",
    "README.md",
    "ROADMAP.md",
    "docs\reference\CONFIG_REFERENCE.md",
    "docs\release\RELEASE_CHECKLIST.md",
    "docs\release\release_candidate_stabilization.md",
    "docs\architecture\review.md",
    "docs\release\comparison_report.md",
    "docs\architecture\architecture_0.2.0-rc1.md",
    "assistant\DOCUMENTATION_POLICY.md",
    "docs\release\ADVISORY_NOTES.md",
    "scripts\run-tests.ps1",
    "scripts\test-boundary-runs.ps1",
    "scripts\test-unsupported-concurrent-run.ps1"
)

foreach ($f in $requiredFiles) {
    $checks.Add((Test-FileExistsCheck -RelativePath $f)) | Out-Null
}

# Optional/reference files
$optionalFiles = @(
    "legacy\wrapper.ps1",
    "configs\sample.stdown.ps1",
    "configs\sample.args_env.ps1",
    "configs\sample.bulk_output.ctrlc.ps1",
    "configs\sample.bulk_output.ps1",
    "configs\sample.echo.ps1",
    "configs\sample.exit_code.ps1",
    "configs\sample.ignore_ctrlc.ps1",
    "configs\sample.ctrlc_counter.ps1",
    "configs\sample.no_output_sleep.ps1",
    "configs\sample.stderr_output.ps1",
    "configs\vaultwarden.template.ps1",
    "tests\stdown.c",
    "tests\ctrlc_counter.c",
    "tests\args_env.c"
)
foreach ($f in $optionalFiles) {
    $checks.Add((Test-FileExistsCheck -RelativePath $f -Severity "Warning")) | Out-Null
}

# 2. Version checks
$commonPath = Join-Path $ProjectRoot "src\common.ps1"
$wrapperPath = Join-Path $ProjectRoot "wrapper-csharphost.ps1"
$readmePath = Join-Path $ProjectRoot "README.md"

$commonText = if (Test-Path $commonPath) { Get-Content -LiteralPath $commonPath -Raw } else { "" }
$wrapperText = if (Test-Path $wrapperPath) { Get-Content -LiteralPath $wrapperPath -Raw } else { "" }
$readmeText = if (Test-Path $readmePath) { Get-Content -LiteralPath $readmePath -Raw } else { "" }

$versionRegex = 'WrapperVersion\s*=\s*"([^"]+)"'
$versionMatch = [regex]::Match($commonText, $versionRegex)
if ($versionMatch.Success -and $versionMatch.Groups[1].Value -eq $ExpectedVersion) {
    $checks.Add((New-CheckResult -Name "WrapperVersion" -Pass $true -Message "WrapperVersion=$($versionMatch.Groups[1].Value)")) | Out-Null
}
else {
    $actual = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { "<not found>" }
    $checks.Add((New-CheckResult -Name "WrapperVersion" -Pass $false -Message "Expected $ExpectedVersion, actual $actual")) | Out-Null
}

$expectedNamespace = "CSharpWrapperHost_v" + ($ExpectedVersion -replace '[^A-Za-z0-9]', '')
# For 0.2.0-rc1 we intentionally use v020rc1 rather than v0200rc1.
if ($ExpectedVersion -eq "0.2.0-rc1") { $expectedNamespace = "CSharpWrapperHost_v020rc1" }
if ($ExpectedVersion -eq "0.2.0-rc2-dev") { $expectedNamespace = "CSharpWrapperHost_v020rc2dev" }

if ($wrapperText -match [regex]::Escape($expectedNamespace)) {
    $checks.Add((New-CheckResult -Name "CSharpHost namespace" -Pass $true -Message "Found namespace $expectedNamespace")) | Out-Null
}
else {
    $checks.Add((New-CheckResult -Name "CSharpHost namespace" -Pass $false -Message "Expected namespace $expectedNamespace not found")) | Out-Null
}

if ($readmeText -match [regex]::Escape($ExpectedVersion)) {
    $checks.Add((New-CheckResult -Name "README version mention" -Pass $true -Message "README mentions $ExpectedVersion")) | Out-Null
}
else {
    $checks.Add((New-CheckResult -Name "README version mention" -Pass $false -Message "README does not mention $ExpectedVersion" -Severity "Warning")) | Out-Null
}

# 3. Control character scan in markdown docs
$markdownFiles = @()
$markdownFiles += Get-ChildItem -Path $ProjectRoot -Filter "*.md" -File -ErrorAction SilentlyContinue
$markdownFiles += Get-ChildItem -Path (Join-Path $ProjectRoot "docs") -Filter "*.md" -File -Recurse -ErrorAction SilentlyContinue

$badControlFiles = @()
foreach ($mf in $markdownFiles) {
    $txt = [System.IO.File]::ReadAllText($mf.FullName, [System.Text.Encoding]::UTF8)
    $bad = $false
    foreach ($ch in $txt.ToCharArray()) {
        $code = [int][char]$ch
        if ($code -lt 32 -and $ch -ne "`n" -and $ch -ne "`t" -and $ch -ne "`r") {
            $bad = $true
            break
        }
    }
    if ($bad) { $badControlFiles += $mf.FullName.Replace($ProjectRoot + "\", "") }
}

if ($badControlFiles.Count -eq 0) {
    $checks.Add((New-CheckResult -Name "Markdown control character scan" -Pass $true -Message "No unexpected control characters found")) | Out-Null
}
else {
    $checks.Add((New-CheckResult -Name "Markdown control character scan" -Pass $false -Message ("Unexpected control characters in: " + ($badControlFiles -join ", ")))) | Out-Null
}

# 4. Stale wording scan. These are warnings because historical docs may intentionally mention old versions.
$stalePatterns = @(
    "Deferred to Step 7",
    "Enable later in Step 7",
    "CSharpHost MVP",
    "Version baseline: 0.1",
    "Baseline version: 0.1"
)
foreach ($pat in $stalePatterns) {
    $hits = @()
    foreach ($mf in $markdownFiles) {
        $txt = Get-Content -LiteralPath $mf.FullName -Raw
        if ($txt -like "*$pat*") { $hits += $mf.FullName.Replace($ProjectRoot + "\", "") }
    }
    if ($hits.Count -eq 0) {
        $checks.Add((New-CheckResult -Name "Stale text scan: $pat" -Pass $true -Message "No hits" -Severity "Warning")) | Out-Null
    }
    else {
        $checks.Add((New-CheckResult -Name "Stale text scan: $pat" -Pass $false -Message ("Hits: " + ($hits -join ", ")) -Severity "Warning")) | Out-Null
    }
}

# 5. Environment capture
$environment = [pscustomobject]@{
    Timestamp = (Get-Date).ToString("o")
    MachineName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    OSVersion = [Environment]::OSVersion.VersionString
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    ProjectRoot = $ProjectRoot
}

# 6. Optional non-interactive tests
$testRun = [pscustomobject]@{
    Requested = [bool]$RunNonInteractiveTests
    ExitCode = $null
    Output = @()
    Passed = $null
}

if ($RunNonInteractiveTests) {
    $runTests = Join-Path $ProjectRoot "scripts\run-tests.ps1"
    if (Test-Path -LiteralPath $runTests) {
        Push-Location $ProjectRoot
        try {
            $output = & $runTests -Implementation CSharpHost 2>&1
            $exit = $LASTEXITCODE
            $testRun.ExitCode = $exit
            $testRun.Output = @($output | ForEach-Object { [string]$_ })
            $testRun.Passed = ($exit -eq 0)
            $checks.Add((New-CheckResult -Name "Non-interactive CSharpHost matrix" -Pass ($exit -eq 0) -Message "ExitCode=$exit")) | Out-Null
        }
        finally {
            Pop-Location
        }
    }
    else {
        $testRun.Passed = $false
        $checks.Add((New-CheckResult -Name "Non-interactive CSharpHost matrix" -Pass $false -Message "scripts\run-tests.ps1 not found")) | Out-Null
    }
}

# Summary
$errorFailures = @($checks | Where-Object { -not $_.Pass -and $_.Severity -eq "Error" })
$warningFailures = @($checks | Where-Object { -not $_.Pass -and $_.Severity -eq "Warning" })
$passedChecks = @($checks | Where-Object { $_.Pass })

$overallPass = ($errorFailures.Count -eq 0)

$checksArray = @($checks | ForEach-Object { $_ })
$manualChecksRequired = @(
    "Ctrl+C interactive test",
    "Console Close test",
    "Logoff/Shutdown VM test",
    "Production-like app validation",
    "Final documentation human review"
)

# Use an ordered hashtable instead of [pscustomobject] here. Windows PowerShell 5.1 can throw
# an ArgumentException when complex generic-list-backed values are embedded directly into a
# [pscustomobject] literal in some environments.
$report = [ordered]@{
    ExpectedVersion = $ExpectedVersion
    OverallPass = $overallPass
    PassedCount = $passedChecks.Count
    ErrorFailureCount = $errorFailures.Count
    WarningFailureCount = $warningFailures.Count
    Environment = $environment
    Checks = $checksArray
    NonInteractiveTests = $testRun
    ManualChecksRequired = $manualChecksRequired
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportJsonPath -Encoding UTF8

if ($GenerateMarkdownReport) {
    $md = New-Object System.Text.StringBuilder
    [void]($md.AppendLine("# Release Validation Report"))
    [void]($md.AppendLine(""))
    [void]($md.AppendLine("- ExpectedVersion: $ExpectedVersion"))
    [void]($md.AppendLine("- OverallPass: **$overallPass**"))
    [void]($md.AppendLine("- Timestamp: $($environment.Timestamp)"))
    [void]($md.AppendLine("- Machine: $($environment.MachineName)"))
    [void]($md.AppendLine("- PowerShell: $($environment.PowerShellVersion)"))
    [void]($md.AppendLine(""))
    [void]($md.AppendLine("## Check summary"))
    [void]($md.AppendLine(""))
    [void]($md.AppendLine("| Check | Severity | Result | Message |"))
    [void]($md.AppendLine("|---|---|---:|---|"))
    foreach ($c in $checks) {
        $status = if ($c.Pass) { "PASS" } else { "FAIL" }
        $msg = ([string]$c.Message).Replace("|", "\\|")
        [void]($md.AppendLine("| $($c.Name) | $($c.Severity) | $status | $msg |"))
    }
    [void]($md.AppendLine(""))
    [void]($md.AppendLine("## Non-interactive tests"))
    [void]($md.AppendLine(""))
    [void]($md.AppendLine("- Requested: $($testRun.Requested)"))
    [void]($md.AppendLine("- ExitCode: $($testRun.ExitCode)"))
    [void]($md.AppendLine("- Passed: $($testRun.Passed)"))
    [void]($md.AppendLine(""))
    [void]($md.AppendLine("## Manual checks still required"))
    foreach ($m in $manualChecksRequired) {
        [void]($md.AppendLine("- [ ] $m"))
    }
    [void]($md.AppendLine(""))
    [void]($md.AppendLine("## Sign-off"))
    [void]($md.AppendLine(""))
    [void]($md.AppendLine("- Manual checks: __________________"))
    [void]($md.AppendLine("- Signed off by: __________________"))
    [void]($md.AppendLine("- Date: __________________"))

    [System.IO.File]::WriteAllText($reportMdPath, $md.ToString(), [System.Text.Encoding]::UTF8)
}

Write-Host "=== Release validation summary ==="
Write-Host "ExpectedVersion : $ExpectedVersion"
Write-Host "OverallPass     : $overallPass"
Write-Host "PassedChecks    : $($passedChecks.Count)"
Write-Host "ErrorFailures   : $($errorFailures.Count)"
Write-Host "WarningFailures : $($warningFailures.Count)"
Write-Host "JSON Report     : $reportJsonPath"
if ($GenerateMarkdownReport) { Write-Host "Markdown Report : $reportMdPath" }

if ($warningFailures.Count -gt 0) {
    Write-Host "Warnings:"
    foreach ($w in $warningFailures) { Write-Host "  [WARN] $($w.Name): $($w.Message)" }
}

if ($errorFailures.Count -gt 0) {
    Write-Host "Errors:"
    foreach ($e in $errorFailures) { Write-Host "  [ERROR] $($e.Name): $($e.Message)" }
    exit 2
}

exit 0
