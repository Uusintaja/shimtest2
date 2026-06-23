$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WorkRoot = Join-Path $ProjectRoot "work\exit_code"
$LogRoot = Join-Path $ProjectRoot "logs"

# Change this value to test argument passing, e.g. 6 or -6.
$ExpectedCode = 7

return @{
    AppPath = Join-Path $ProjectRoot "bin\exit_code.exe"
    AppArgs = @([string]$ExpectedCode)
    WorkingDirectory = $WorkRoot
    CreateDirectories = @($WorkRoot, $LogRoot)
    LogFilePath = Join-Path $LogRoot "wrapper.exit_code.log"
    AppOutputLogFilePath = Join-Path $LogRoot "app.exit_code.output.log"
    StripAnsiSequences = $true
    InputMode = "None"
    EnableShutdownSentinel = $true
    PostActions = @(
        @{ Name="exit code matches configured arg"; Type="ExitCodeEquals"; ExpectedExitCode=$ExpectedCode; TreatFailureAsError=$false },
        @{ Name="output states configured exit code"; Type="RegexOutputContains"; Pattern=("code " + [regex]::Escape([string]$ExpectedCode)); TreatFailureAsError=$true }
    )
}
