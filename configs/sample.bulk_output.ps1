$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WorkRoot = Join-Path $ProjectRoot "work\bulk_output"
$LogRoot = Join-Path $ProjectRoot "logs"

return @{
    AppPath = Join-Path $ProjectRoot "bin\bulk_output.exe"
    WorkingDirectory = $WorkRoot
    CreateDirectories = @($WorkRoot, $LogRoot)
    LogFilePath = Join-Path $LogRoot "wrapper.bulk_output.log"
    AppOutputLogFilePath = Join-Path $LogRoot "app.bulk_output.output.log"
    OutputEncoding = "utf-8"
    StripAnsiSequences = $true
    InputMode = "None"
    EnableShutdownSentinel = $true
    PostActions = @(
        @{ Name="exit code is zero"; Type="ExitCodeEquals"; ExpectedExitCode=0; TreatFailureAsError=$true },
        @{ Name="last bulk line seen"; Type="RegexOutputContains"; Pattern="bulk-line:19999"; TreatFailureAsError=$true }
    )
}
