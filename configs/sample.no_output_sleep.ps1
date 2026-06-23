$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WorkRoot = Join-Path $ProjectRoot "work\no_output_sleep"
$LogRoot = Join-Path $ProjectRoot "logs"

return @{
    AppPath = Join-Path $ProjectRoot "bin\no_output_sleep.exe"
    AppArgs = @("3")
    WorkingDirectory = $WorkRoot
    CreateDirectories = @($WorkRoot, $LogRoot)
    LogFilePath = Join-Path $LogRoot "wrapper.no_output_sleep.log"
    AppOutputLogFilePath = Join-Path $LogRoot "app.no_output_sleep.output.log"
    OutputEncoding = "utf-8"
    StripAnsiSequences = $true
    InputMode = "None"
    EnableShutdownSentinel = $true
    PostActions = @(
        @{ Name="exit code is zero"; Type="ExitCodeEquals"; ExpectedExitCode=0; TreatFailureAsError=$true },
        @{ Name="no output expected"; Type="CustomPowerShell"; TreatFailureAsError=$true; ScriptBlock={ param($Config,$Result,$CapturedOutput) @{ Success = ([string]::IsNullOrEmpty($CapturedOutput)); Message = "CapturedOutputLength=$($CapturedOutput.Length)" } } }
    )
}
