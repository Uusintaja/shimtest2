$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WorkRoot = Join-Path $ProjectRoot "work\ignore_ctrlc"
$LogRoot = Join-Path $ProjectRoot "logs"

return @{
    AppPath = Join-Path $ProjectRoot "bin\ignore_ctrlc.exe"
    WorkingDirectory = $WorkRoot
    CreateDirectories = @($WorkRoot, $LogRoot)
    LogFilePath = Join-Path $LogRoot "wrapper.ignore_ctrlc.log"
    AppOutputLogFilePath = Join-Path $LogRoot "app.ignore_ctrlc.output.log"
    OutputEncoding = "utf-8"
    InputEncoding = "utf-8"
    StripAnsiSequences = $true
    InputMode = "None"
    CtrlCTimeoutSeconds = 2
    KillOnTimeout = $true
    EnableShutdownSentinel = $true
    PostActions = @(
        @{ Name="process was killed after ignored Ctrl+C"; Type="CustomPowerShell"; TreatFailureAsError=$true; ScriptBlock={ param($Config,$Result,$CapturedOutput) @{ Success = ([bool]$Result.WasKilled -and [bool]$Result.TimedOut); Message = "WasKilled=$($Result.WasKilled), TimedOut=$($Result.TimedOut)" } } },
        @{ Name="output saw ignored Ctrl+C"; Type="RegexOutputContains"; Pattern="intentionally ignored"; TreatFailureAsError=$true }
    )
}
