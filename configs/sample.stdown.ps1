<#
.SYNOPSIS
    Sample configuration for testing the generic wrapper with stdown.c/app.exe.

.DESCRIPTION
    This file is app-specific test data. The wrapper core must not hard-code these assumptions.

.USAGE
    From Windows PowerShell 5.1:
        . .\src\common.ps1
        $config = . .\configs\sample.stdown.ps1
#>

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WorkRoot = Join-Path $ProjectRoot "work\stdown"
$OutputRoot = Join-Path $WorkRoot "output"
$AppPath = Join-Path $ProjectRoot "bin\app.exe"
$LogRoot = Join-Path $ProjectRoot "logs"

return @{
    AppPath = $AppPath
    AppArgs = @()
    WorkingDirectory = $WorkRoot

    EnvironmentVariables = @{
        APP_CONFIG_PATH = $WorkRoot
    }
    InheritParentEnvironment = $true

    CreateDirectories = @(
        $WorkRoot,
        $OutputRoot,
        $LogRoot
    )

    LogFilePath = Join-Path $LogRoot "wrapper.stdown.log"
    AppOutputLogFilePath = Join-Path $LogRoot "app.stdown.output.log"

    OutputEncoding = "utf-8"
    InputEncoding = "utf-8"

    # ConPTY emits a terminal rendering stream. For this line-oriented test we want clean app logs.
    StripAnsiSequences = $true

    # stdown.c does not read stdin, so None avoids unnecessary input thread during this test.
    InputMode = "None"

    CtrlCTimeoutSeconds = 5
    KillOnTimeout = $true

    EnableCtrlCForwarding = $true
    EnableCtrlBreakEmergencyExit = $true
    EnableConsoleCloseHandling = $true
    EnableShutdownSentinel = $true
    ShutdownMode = "BestEffort"

    PostActions = @(
        @{
            Name = "stdown output file contains done"
            Type = "FileContentEquals"
            Path = Join-Path $OutputRoot "output.txt"
            ExpectedContent = "done"
            TrimEnd = $true
            TreatFailureAsError = $true
        },
        @{
            Name = "app exit code is zero"
            Type = "ExitCodeEquals"
            ExpectedExitCode = 0
            TreatFailureAsError = $true
        },
        @{
            Name = "app reported Ctrl+C capture"
            Type = "RegexOutputContains"
            # Keep this assertion ASCII-only for Windows PowerShell 5.1 encoding robustness.
            # The stronger Chinese text assertion is intentionally avoided in config files unless
            # the file is guaranteed to be saved as UTF-8 with BOM.
            Pattern = "Ctrl\+C"
            TreatFailureAsError = $true
        }
    )
}
