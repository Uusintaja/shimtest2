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
    CtrlCGracePeriodMs = 5000
    CtrlCUnresponsivePolicy = "Kill"
    PostActions = @(
        @{ Name="trigger reason is CtrlC"; Type="CustomPowerShell"; TreatFailureAsError=$true; ScriptBlock={ param($Config,$Result,$CapturedOutput) @{ Success = ([string]$Result.TerminalTrigger.Kind -eq "CtrlC"); Message = "TerminalTrigger=$($Result.TerminalTrigger.Kind)" } } },
        @{ Name="process exited by default Ctrl+C"; Type="CustomPowerShell"; TreatFailureAsError=$true; ScriptBlock={ param($Config,$Result,$CapturedOutput) @{ Success = ([int]$Result.AppState.ExitCode -eq -1073741510); Message = "AppExitCode=$($Result.AppState.ExitCode)" } } },
        @{ Name="not killed by wrapper"; Type="CustomPowerShell"; TreatFailureAsError=$true; ScriptBlock={ param($Config,$Result,$CapturedOutput) @{ Success = (-not [bool]$Result.AppState.WasKilled -and -not [bool]$Result.AppState.GracefulExitTimedOut); Message = "WasKilled=$($Result.AppState.WasKilled), GracefulExitTimedOut=$($Result.AppState.GracefulExitTimedOut)" } } }
    )
}
