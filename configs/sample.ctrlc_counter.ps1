$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WorkRoot = Join-Path $ProjectRoot "work\ctrlc_counter"
$LogRoot = Join-Path $ProjectRoot "logs"

return @{
    AppPath = Join-Path $ProjectRoot "bin\ctrlc_counter.exe"
    AppArgs = @()
    WorkingDirectory = $WorkRoot
    EnvironmentVariables = @{}
    CreateDirectories = @($WorkRoot, $LogRoot)
    LogFilePath = Join-Path $LogRoot "wrapper.ctrlc_counter.log"
    AppOutputLogFilePath = Join-Path $LogRoot "app.ctrlc_counter.output.log"
    OutputEncoding = "utf-8"
    StripAnsiSequences = $true
    InputMode = "None"
    EnableShutdownSentinel = $true

    CtrlCGracePeriodMs = 500
    CtrlCUnresponsivePolicy = "Continue"

    PostActions = @(
        @{ Name="exit code is zero"; Type="ExitCodeEquals"; ExpectedExitCode=0; TreatFailureAsError=$true },
        @{ Name="triple ctrl+c threshold reached"; Type="RegexOutputContains"; Pattern="Triple Ctrl\+C threshold reached"; TreatFailureAsError=$true },
        @{ Name="three ctrl+c sends recorded"; Type="CustomPowerShell"; TreatFailureAsError=$true; ScriptBlock={ param($Config,$Result,$CapturedOutput) @{ Success = ([int]$Result.EventAudit.CtrlCSentCount -ge 3); Message = "CtrlCSentCount=$($Result.EventAudit.CtrlCSentCount)" } } }
    )
}
