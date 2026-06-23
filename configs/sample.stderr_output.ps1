$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WorkRoot = Join-Path $ProjectRoot "work\stderr_output"
$LogRoot = Join-Path $ProjectRoot "logs"

return @{
    AppPath = Join-Path $ProjectRoot "bin\stderr_output.exe"
    WorkingDirectory = $WorkRoot
    CreateDirectories = @($WorkRoot, $LogRoot)
    LogFilePath = Join-Path $LogRoot "wrapper.stderr_output.log"
    AppOutputLogFilePath = Join-Path $LogRoot "app.stderr_output.output.log"
    OutputEncoding = "utf-8"
    StripAnsiSequences = $true
    InputMode = "None"
    EnableShutdownSentinel = $true
    PostActions = @(
        @{ Name="exit code is zero"; Type="ExitCodeEquals"; ExpectedExitCode=0; TreatFailureAsError=$true },
        @{ Name="stdout captured"; Type="RegexOutputContains"; Pattern="stdout line 1"; TreatFailureAsError=$true },
        @{ Name="stderr captured in ConPTY stream"; Type="RegexOutputContains"; Pattern="stderr line 1"; TreatFailureAsError=$true }
    )
}
