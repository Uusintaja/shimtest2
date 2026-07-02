<# Sample config for future echo_stdin.exe test. #>
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WorkRoot = Join-Path $ProjectRoot "work\echo"
$LogRoot = Join-Path $ProjectRoot "logs"

return @{
    AppPath = Join-Path $ProjectRoot "bin\echo_stdin.exe"
    AppArgs = @()
    WorkingDirectory = $WorkRoot
    EnvironmentVariables = @{}
    CreateDirectories = @($WorkRoot, $LogRoot)
    LogFilePath = Join-Path $LogRoot "wrapper.echo.log"
    AppOutputLogFilePath = Join-Path $LogRoot "app.echo.output.log"
    OutputEncoding = "utf-8"
    InputEncoding = "utf-8"
    InputMode = "Line"
    CtrlCGracePeriodMs = 5000
    CtrlCUnresponsivePolicy = "Kill"
    KillOnTimeout = $true
    EnableShutdownSentinel = $true
    StripAnsiSequences = $true
    PostActions = @(
        @{
            Name = "echo process exit code is zero"
            Type = "ExitCodeEquals"
            ExpectedExitCode = 0
            TreatFailureAsError = $true
        },
        @{
            Name = "quit was echoed"
            Type = "RegexOutputContains"
            Pattern = "echo:quit"
            TreatFailureAsError = $true
        }
    )
}
