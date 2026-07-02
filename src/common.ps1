<#
.SYNOPSIS
    Shared configuration, result, logging, and post-action helpers for the ConPTY wrapper project.

.DESCRIPTION
    This file is intentionally implementation-neutral. Both implementations must use the same
    config/result schema so that PowerShell-main and CSharpHost versions can be compared fairly.

    Compatible target: Windows PowerShell 5.1.
#>

Set-StrictMode -Version 2.0

function New-WrapperDefaultConfig {
    <#
    .SYNOPSIS
        Creates the default wrapper configuration hashtable.

    .OUTPUTS
        [hashtable]
    #>
    [CmdletBinding()]
    param()

    return @{
        # Required by caller
        AppPath = $null

        # Process startup
        AppArgs = @()
        WorkingDirectory = $null
        EnvironmentVariables = @{}
        InheritParentEnvironment = $true
        # Log env override names by default, but not values. Values may contain tokens/secrets.
        LogEnvironmentVariableValues = $false
        CreateDirectories = @()

        # Logging/output
        LogFilePath = ".\wrapper.log"
        AppOutputLogFilePath = $null
        OutputEncoding = "utf-8"
        InputEncoding = "utf-8"
        StripAnsiSequences = $false
        # Normal AppExited path should display/drain remaining ConPTY output before summary/exit.
        # Close/Shutdown still use their own short best-effort drain.
        NormalExitOutputDrainMilliseconds = 10000
        # Normal AppExited path explicitly closes HPCON after the child process exits, then drains
        # remaining ConPTY output until reader EOF + queue empty, bounded by NormalExitOutputDrainMilliseconds.
        # Quiet period remains only as fallback if EOF is still not observed.
        NormalExitOutputQuietMilliseconds = 250
        NormalExitClosePseudoConsoleBeforeDrain = $true

        # Input
        InputMode = "Line" # None / Line supported in rc1; Char is reserved/experimental.

        # Timeouts and lifecycle
        # Ctrl+C graceful-exit window. If null, CSharpHost chooses by CtrlCUnresponsivePolicy:
        # Kill => 5000ms, Continue => 1000ms.
        CtrlCGracePeriodMs = $null
        CtrlCUnresponsivePolicy = "Kill" # Kill / Continue
        KillOnTimeout = $true

        # Signal handling
        EnableCtrlCForwarding = $true
        EnableCtrlBreakEmergencyExit = $true
        EnableConsoleCloseHandling = $true
        # CTRL_CLOSE_EVENT is time-limited by Windows. These defaults reserve time for wrapper-side
        # minimal logging/kill/output-drain instead of spending the whole budget waiting for app exit.
        # Dedicated close-event budget. Do not reuse CtrlCGracePeriodMs here.
        # CTRL_CLOSE_EVENT is heavily time-limited; default app wait is intentionally short.
        CloseAppWaitMilliseconds = 2000
        CloseHandlerBudgetMilliseconds = 3000
        CloseReserveMilliseconds = 800
        # Do not manipulate the visible console window in CTRL_CLOSE_EVENT. It was tested and removed
        # because it can freeze the closing console before Ctrl+C reaches the app.
        CloseSkipPostActions = $true

        EnableShutdownSentinel = $true
        ShutdownMode = "BestEffort" # BestEffort supported in rc1; CancelAndReissue is reserved.
        # Dedicated shutdown/logoff budget. Do not reuse Ctrl+C or Close budgets.
        ShutdownAppWaitMilliseconds = 2000
        ShutdownHandlerBudgetMilliseconds = 3000
        ShutdownReserveMilliseconds = 800
        ShutdownSkipPostActions = $true

        # Extension
        ContentMatcher = $null
        PostActions = @()

        # Metadata
        WrapperVersion = "0.2.0-rc2-dev"
    }
}

function Copy-WrapperHashtable {
    <#
    .SYNOPSIS
        Performs a shallow copy of a hashtable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$InputHashtable
    )

    $copy = @{}
    foreach ($key in $InputHashtable.Keys) {
        $copy[$key] = $InputHashtable[$key]
    }
    return $copy
}

function Merge-WrapperConfig {
    <#
    .SYNOPSIS
        Merges user config into default config.

    .DESCRIPTION
        This is intentionally simple and predictable: top-level keys from UserConfig replace defaults.
        Nested hashtables are not deeply merged except EnvironmentVariables, where values are merged.

    .PARAMETER UserConfig
        User supplied hashtable.

    .OUTPUTS
        [hashtable]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [hashtable]$UserConfig
    )

    $config = New-WrapperDefaultConfig
    if ($null -eq $UserConfig) { return $config }

    foreach ($key in $UserConfig.Keys) {
        if ($key -eq "EnvironmentVariables" -and $UserConfig[$key] -is [hashtable]) {
            $mergedEnv = @{}
            foreach ($envKey in $config.EnvironmentVariables.Keys) { $mergedEnv[$envKey] = $config.EnvironmentVariables[$envKey] }
            foreach ($envKey in $UserConfig[$key].Keys) {
                $envValue = $UserConfig[$key][$envKey]
                if ($null -eq $envValue) { $mergedEnv[$envKey] = $null }
                else { $mergedEnv[$envKey] = [string]$envValue }
            }
            $config[$key] = $mergedEnv
        }
        else {
            $config[$key] = $UserConfig[$key]
        }
    }

    return $config
}

function Assert-WrapperConfig {
    <#
    .SYNOPSIS
        Validates common wrapper configuration and throws on invalid values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )

    if ([string]::IsNullOrWhiteSpace([string]$Config.AppPath)) {
        throw "Config.AppPath is required."
    }

    $validInputModes = @("None", "Line")
    if ($validInputModes -notcontains [string]$Config.InputMode) {
        throw "Config.InputMode must be one of: $($validInputModes -join ', '). Actual: $($Config.InputMode). InputMode=Char is reserved/experimental and is not supported in rc1."
    }

    $validShutdownModes = @("BestEffort")
    if ($validShutdownModes -notcontains [string]$Config.ShutdownMode) {
        throw "Config.ShutdownMode must be one of: $($validShutdownModes -join ', '). Actual: $($Config.ShutdownMode). CancelAndReissue is reserved and not implemented in rc1."
    }

    $validCtrlCUnresponsivePolicies = @("Kill", "Continue")
    if ($validCtrlCUnresponsivePolicies -notcontains [string]$Config.CtrlCUnresponsivePolicy) {
        throw "Config.CtrlCUnresponsivePolicy must be one of: $($validCtrlCUnresponsivePolicies -join ', '). Actual: $($Config.CtrlCUnresponsivePolicy)"
    }

    foreach ($name in @("CtrlCGracePeriodMs", "CloseAppWaitMilliseconds", "CloseHandlerBudgetMilliseconds", "CloseReserveMilliseconds", "ShutdownAppWaitMilliseconds", "ShutdownHandlerBudgetMilliseconds", "ShutdownReserveMilliseconds", "NormalExitOutputDrainMilliseconds", "NormalExitOutputQuietMilliseconds")) {
        if ($Config.ContainsKey($name)) {
            $value = [int]$Config[$name]
            if ($value -lt 0) { throw "Config.$name must be >= 0. Actual: $value" }
        }
    }


    if ($Config.ContainsKey("CloseHandlerBudgetMilliseconds") -and $Config.ContainsKey("CloseReserveMilliseconds")) {
        if ([int]$Config["CloseReserveMilliseconds"] -ge [int]$Config["CloseHandlerBudgetMilliseconds"]) {
            throw "Config.CloseReserveMilliseconds must be less than Config.CloseHandlerBudgetMilliseconds."
        }
    }
    if ($Config.ContainsKey("ShutdownHandlerBudgetMilliseconds") -and $Config.ContainsKey("ShutdownReserveMilliseconds")) {
        if ([int]$Config["ShutdownReserveMilliseconds"] -ge [int]$Config["ShutdownHandlerBudgetMilliseconds"]) {
            throw "Config.ShutdownReserveMilliseconds must be less than Config.ShutdownHandlerBudgetMilliseconds."
        }
    }

    if ($null -ne $Config.WorkingDirectory -and -not [string]::IsNullOrWhiteSpace([string]$Config.WorkingDirectory)) {
        # Do not require it exists here if CreateDirectories contains it, but warn through caller logging later.
    }

    return $true
}

function Initialize-WrapperDirectories {
    <#
    .SYNOPSIS
        Creates configured directories and log parent directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )

    $dirs = @()
    if ($Config.ContainsKey("CreateDirectories") -and $null -ne $Config.CreateDirectories) {
        foreach ($dir in $Config.CreateDirectories) {
            if (-not [string]::IsNullOrWhiteSpace([string]$dir)) { $dirs += [string]$dir }
        }
    }

    foreach ($filePathKey in @("LogFilePath", "AppOutputLogFilePath")) {
        $path = $Config[$filePathKey]
        if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
            $parent = Split-Path -Parent ([string]$path)
            if (-not [string]::IsNullOrWhiteSpace($parent)) { $dirs += $parent }
        }
    }

    foreach ($dir in ($dirs | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

function New-WrapperResult {
    <#
    .SYNOPSIS
        Creates a default wrapper result hashtable.
    #>
    [CmdletBinding()]
    param(
        [string]$Implementation = "Unknown",
        [hashtable]$Config = $null
    )

    $now = Get-Date
    $result = @{
        WrapperVersion = if ($null -ne $Config -and $Config.ContainsKey("WrapperVersion")) { [string]$Config.WrapperVersion } else { "unknown" }
        Implementation = $Implementation

        AppPath = if ($null -ne $Config) { $Config.AppPath } else { $null }
        AppPid = $null

        StartTime = $now
        EndTime = $null
        DurationMs = $null

        TriggerReason = "Unknown"
        FinalState = "Unknown"

        AppExitCode = $null
        WasKilled = $false
        TimedOut = $false

        CloseEventReceived = $false
        ShutdownEventReceived = $false

        StdoutBytes = 0
        OutputLines = 0

        PostActions = @()
        Errors = @()
    }

    return $result
}

function Complete-WrapperResult {
    <#
    .SYNOPSIS
        Fills EndTime and DurationMs on a result object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Result
    )

    $end = Get-Date
    $Result.EndTime = $end
    if ($null -ne $Result.StartTime) {
        $Result.DurationMs = [int64](New-TimeSpan -Start ([datetime]$Result.StartTime) -End $end).TotalMilliseconds
    }
    return $Result
}

function Add-WrapperError {
    <#
    .SYNOPSIS
        Appends an error record string to Result.Errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [hashtable]$Result,
        [Parameter(Mandatory=$true)] [string]$Message
    )

    $Result.Errors += @($Message)
}

function Get-WrapperTextEncoding {
    <#
    .SYNOPSIS
        Resolves a text encoding name to System.Text.Encoding.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$Name
    )

    switch -Regex ($Name.ToLowerInvariant()) {
        "^utf-?8$" { return [System.Text.Encoding]::UTF8 }
        "^utf-?16$" { return [System.Text.Encoding]::Unicode }
        "^unicode$" { return [System.Text.Encoding]::Unicode }
        "^ascii$" { return [System.Text.Encoding]::ASCII }
        "^default$" { return [System.Text.Encoding]::Default }
        default { return [System.Text.Encoding]::GetEncoding($Name) }
    }
}


function Remove-WrapperAnsiSequences {
    <#
    .SYNOPSIS
        Removes common ANSI/VT control sequences from ConPTY terminal output.

    .DESCRIPTION
        ConPTY output is a terminal rendering stream, not a clean stdout byte stream. It may contain
        CSI, OSC, DCS, PM/APC and single-character ESC sequences emitted by conhost/terminal state.
        This sanitizer is intended for plain-text logs and simple regex post-actions. It is not a
        full terminal emulator and must not be used when exact TUI replay is required.

        Important for Windows PowerShell 5.1: do not use the PowerShell 7 escape literal `e here.
        Windows PowerShell 5.1 does not support `e as ESC. Always construct ESC as [char]27.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $esc = [string][char]27
    $bel = [string][char]7
    $escRe = [regex]::Escape($esc)
    $belRe = [regex]::Escape($bel)

    $s = $Text

    # OSC: ESC ] ... BEL  or  ESC ] ... ESC \
    $s = [regex]::Replace($s, $escRe + "\][\s\S]*?(?:" + $belRe + "|" + $escRe + "\\)", "")

    # DCS/PM/APC/SOS string controls: ESC P/^/_/X ... ESC \
    $s = [regex]::Replace($s, $escRe + "[P\^_X][\s\S]*?" + $escRe + "\\", "")

    # CSI: ESC [ params/intermediates final-byte
    $s = [regex]::Replace($s, $escRe + "\[[0-?]*[ -/]*[@-~]", "")

    # Single-character ESC sequences: ESC followed by one byte in final range.
    $s = [regex]::Replace($s, $escRe + "[@-Z\\-_]", "")

    # C0 controls except CR/LF/TAB. This removes BEL if left behind.
    $s = [regex]::Replace($s, "[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]", "")

    return $s
}

function Write-WrapperLog {
    <#
    .SYNOPSIS
        Writes one wrapper log line to configured log file.

    .DESCRIPTION
        This function deliberately catches logging failures and writes a warning to host instead.
        Logging failure must not kill the wrapped process.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [hashtable]$Config,
        [Parameter(Mandatory=$true)] [string]$Message,
        [ValidateSet("TRACE", "DEBUG", "INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $runPrefix = ""
    try {
        if ($Config.ContainsKey("RunId") -and -not [string]::IsNullOrWhiteSpace([string]$Config["RunId"])) {
            $runPrefix = "[RunId=$($Config["RunId"])]"
        }
    } catch {}
    $line = "[$timestamp][$Level]$runPrefix $Message"

    $path = $Config.LogFilePath
    if ([string]::IsNullOrWhiteSpace([string]$path)) { return }

    try {
        $encoding = Get-WrapperTextEncoding -Name "utf-8"
        [System.IO.File]::AppendAllText([string]$path, $line + [Environment]::NewLine, $encoding)
    }
    catch {
        Write-Warning "Failed to write wrapper log '$path': $_"
    }
}

function ConvertTo-WrapperJson {
    <#
    .SYNOPSIS
        Converts a wrapper object to JSON in PowerShell 5.1-compatible way.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] $InputObject,
        [int]$Depth = 8
    )

    return ($InputObject | ConvertTo-Json -Depth $Depth)
}

function Test-WrapperFileContentEquals {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [hashtable]$Action
    )

    $path = [string]$Action.Path
    $expected = [string]$Action.ExpectedContent
    $trimEnd = $false
    if ($Action.ContainsKey("TrimEnd")) { $trimEnd = [bool]$Action.TrimEnd }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @{ Success = $false; Message = "File does not exist: $path" }
    }

    $actual = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    if ($trimEnd) {
        $actual = $actual.TrimEnd("`r", "`n", " ", "`t")
        $expected = $expected.TrimEnd("`r", "`n", " ", "`t")
    }

    if ($actual -eq $expected) {
        return @{ Success = $true; Message = "File content matched: $path" }
    }

    return @{ Success = $false; Message = "File content mismatch: $path. Expected=[$expected], Actual=[$actual]" }
}

function Invoke-WrapperPostActions {
    <#
    .SYNOPSIS
        Runs generic post actions against wrapper result/config.

    .DESCRIPTION
        Post actions are intentionally generic. App-specific validation must be expressed as data,
        not hard-coded into wrapper core.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [hashtable]$Config,
        [Parameter(Mandatory=$true)] [hashtable]$Result,
        [string]$CapturedOutput = ""
    )

    $actions = @()
    if ($Config.ContainsKey("PostActions") -and $null -ne $Config.PostActions) {
        $actions = @($Config.PostActions)
    }

    foreach ($action in $actions) {
        $type = [string]$action.Type
        $name = if ($action.ContainsKey("Name")) { [string]$action.Name } else { $type }
        $treatFailureAsError = $false
        if ($action.ContainsKey("TreatFailureAsError")) { $treatFailureAsError = [bool]$action.TreatFailureAsError }

        $record = @{
            Name = $name
            Type = $type
            Success = $false
            Message = $null
        }

        try {
            switch ($type) {
                "FileExists" {
                    $path = [string]$action.Path
                    if (Test-Path -LiteralPath $path -PathType Leaf) {
                        $record.Success = $true
                        $record.Message = "File exists: $path"
                    }
                    else {
                        $record.Message = "File does not exist: $path"
                    }
                }

                "FileContentEquals" {
                    $r = Test-WrapperFileContentEquals -Action $action
                    $record.Success = [bool]$r.Success
                    $record.Message = [string]$r.Message
                }

                "ExitCodeEquals" {
                    $expected = [int]$action.ExpectedExitCode
                    if ($null -ne $Result.AppExitCode -and [int]$Result.AppExitCode -eq $expected) {
                        $record.Success = $true
                        $record.Message = "Exit code matched: $expected"
                    }
                    else {
                        $record.Message = "Exit code mismatch. Expected=$expected, Actual=$($Result.AppExitCode)"
                    }
                }

                "RegexOutputContains" {
                    $pattern = [string]$action.Pattern
                    if ($CapturedOutput -match $pattern) {
                        $record.Success = $true
                        $record.Message = "Captured output matched regex: $pattern"
                    }
                    else {
                        $record.Message = "Captured output did not match regex: $pattern"
                    }
                }

                "CustomPowerShell" {
                    $scriptBlock = $action.ScriptBlock
                    if ($null -eq $scriptBlock -or -not ($scriptBlock -is [scriptblock])) {
                        throw "CustomPowerShell action requires ScriptBlock."
                    }
                    $customResult = & $scriptBlock -Config $Config -Result $Result -CapturedOutput $CapturedOutput
                    if ($customResult -is [hashtable]) {
                        $record.Success = [bool]$customResult.Success
                        $record.Message = [string]$customResult.Message
                    }
                    else {
                        $record.Success = [bool]$customResult
                        $record.Message = "CustomPowerShell returned: $customResult"
                    }
                }

                default {
                    throw "Unknown post action type: $type"
                }
            }
        }
        catch {
            $record.Success = $false
            $record.Message = "Post action failed with exception: $_"
        }

        $Result.PostActions += @($record)
        if (-not $record.Success -and $treatFailureAsError) {
            Add-WrapperError -Result $Result -Message "PostAction '$name' failed: $($record.Message)"
        }
    }

    return $Result.PostActions
}


function Clear-WrapperConsoleInputBuffer {
    <#
    .SYNOPSIS
        Best-effort drain of pending console key input.

    .DESCRIPTION
        Useful after Ctrl+C-heavy tests and before returning to an interactive PowerShell prompt.
        This is best-effort only; it is skipped when input is redirected or console APIs are unavailable.
    #>
    [CmdletBinding()]
    param()

    try {
        while ([Console]::KeyAvailable) {
            [void][Console]::ReadKey($true)
        }
    }
    catch {
        # Non-interactive host or redirected input. Ignore.
    }
}

function Show-WrapperResultSummary {
    <#
    .SYNOPSIS
        Prints a compact human-readable result summary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [hashtable]$Result
    )

    Write-Host "=== Wrapper Result ==="
    Write-Host "Implementation : $($Result.Implementation)"
    Write-Host "TriggerReason  : $($Result.TriggerReason)"
    Write-Host "FinalState     : $($Result.FinalState)"
    Write-Host "AppExitCode    : $($Result.AppExitCode)"
    Write-Host "WasKilled      : $($Result.WasKilled)"
    Write-Host "TimedOut       : $($Result.TimedOut)"
    Write-Host "DurationMs     : $($Result.DurationMs)"
    Write-Host "Errors         : $(@($Result.Errors).Count)"
    if (@($Result.PostActions).Count -gt 0) {
        Write-Host "PostActions:"
        foreach ($pa in $Result.PostActions) {
            $status = if ($pa.Success) { "PASS" } else { "FAIL" }
            Write-Host "  [$status] $($pa.Name): $($pa.Message)"
        }
    }
}
