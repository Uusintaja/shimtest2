$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WorkRoot = Join-Path $ProjectRoot "work\bulk_output_ctrlc"
$LogRoot = Join-Path $ProjectRoot "logs"

return @{
    AppPath = Join-Path $ProjectRoot "bin\bulk_output.exe"
    WorkingDirectory = $WorkRoot
    CreateDirectories = @($WorkRoot, $LogRoot)
    LogFilePath = Join-Path $LogRoot "wrapper.bulk_output.ctrlc.log"
    AppOutputLogFilePath = Join-Path $LogRoot "app.bulk_output.ctrlc.output.log"
    OutputEncoding = "utf-8"
    StripAnsiSequences = $true
    InputMode = "None"
    EnableShutdownSentinel = $true
    CtrlCTimeoutSeconds = 5
    PostActions = @(
        @{ Name="trigger reason is CtrlC"; Type="CustomPowerShell"; TreatFailureAsError=$true; ScriptBlock={ param($Config,$Result,$CapturedOutput) @{ Success = ([string]$Result.TriggerReason -eq "CtrlC"); Message = "TriggerReason=$($Result.TriggerReason)" } } },
        @{ Name="process exited by default Ctrl+C"; Type="CustomPowerShell"; TreatFailureAsError=$true; ScriptBlock={ param($Config,$Result,$CapturedOutput) @{ Success = ([int]$Result.AppExitCode -eq -1073741510); Message = "AppExitCode=$($Result.AppExitCode)" } } },
        @{ Name="not killed by wrapper"; Type="CustomPowerShell"; TreatFailureAsError=$true; ScriptBlock={ param($Config,$Result,$CapturedOutput) @{ Success = (-not [bool]$Result.WasKilled -and -not [bool]$Result.TimedOut); Message = "WasKilled=$($Result.WasKilled), TimedOut=$($Result.TimedOut)" } } }
    )
}
