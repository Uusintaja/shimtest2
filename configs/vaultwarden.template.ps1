<#
.SYNOPSIS
    Template config for running a self-compiled Windows vaultwarden.exe with wrapper-csharphost.ps1.

.DESCRIPTION
    Assumed deployment layout:

        <ProjectRoot>\
        ├─ wrapper-csharphost.ps1
        ├─ src\common.ps1
        ├─ configs\vaultwarden.ps1
        ├─ logs\                         # wrapper logs / wrapper-captured terminal output
        └─ bin\
           ├─ myWinVaultData\
           │  ├─ .env
           │  ├─ cert\
           │  ├─ data\
           │  └─ logs\                   # vaultwarden's own logs
           └─ VaultCore\
              ├─ vaultwarden.exe
              └─ web-vault\

    This config preserves the validated startvault.ps1 behavior:
      - WorkingDirectory = bin\VaultCore
      - ENV_FILE = bin\myWinVaultData\.env
      - vaultwarden's own logs remain under bin\myWinVaultData\logs
      - wrapper logs remain under <ProjectRoot>\logs

.NOTES
    AppOutputLogFilePath is wrapper auxiliary observability, not vaultwarden's authoritative log.
    vaultwarden's own log archive is implemented as a normal-path PostAction only.
#>

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$BaseDir = Join-Path $ProjectRoot "bin"

$CoreDir = Join-Path $BaseDir "VaultCore"
$AppDataDir = Join-Path $BaseDir "myWinVaultData"
$VaultwardenLogDir = Join-Path $AppDataDir "logs"
$WrapperLogDir = Join-Path $ProjectRoot "logs"
$EnvFilePath = Join-Path $AppDataDir ".env"

return @{
    AppPath = Join-Path $CoreDir "vaultwarden.exe"
    AppArgs = @()
    WorkingDirectory = $CoreDir

    EnvironmentVariables = @{
        ENV_FILE = $EnvFilePath
    }
    InheritParentEnvironment = $true
    LogEnvironmentVariableValues = $false

    CreateDirectories = @(
        $AppDataDir,
        $VaultwardenLogDir,
        $WrapperLogDir
    )

    # Wrapper lifecycle log.
    LogFilePath = Join-Path $WrapperLogDir "wrapper.vaultwarden.log"

    # Wrapper-captured terminal output. This is not vaultwarden's authoritative application log.
    AppOutputLogFilePath = Join-Path $WrapperLogDir "wrapper.vaultwarden.output.log"

    OutputEncoding = "utf-8"
    InputEncoding = "utf-8"
    StripAnsiSequences = $true
    InputMode = "None"

    EnableCtrlCForwarding = $true

    # Validated vaultwarden Ctrl+C response is fast (~100ms on the user's real machine).
    # Keep 5s as a conservative normal-path budget.
    CtrlCGracePeriodMs = 5000
    CtrlCUnresponsivePolicy = "Kill"

    KillOnTimeout = $true
    EnableCtrlBreakEmergencyExit = $true

    EnableConsoleCloseHandling = $true

    # Validated close response is fast. Keep 3s to tolerate slower machines / active requests.
    CloseAppWaitMilliseconds = 3000
    CloseHandlerBudgetMilliseconds = 4500
    CloseReserveMilliseconds = 1000

    # IMPORTANT:
    # Close best-effort is handled inside the C# console close callback. PowerShell PostActions
    # are not guaranteed to run after CTRL_CLOSE_EVENT, even if this is set to $false.
    # Keep this true unless you explicitly accept that Close post-actions are opportunistic only.
    CloseSkipPostActions = $true

    EnableShutdownSentinel = $true
    ShutdownMode = "BestEffort"

    # Validated logoff/shutdown response is fast, but keep 3s to tolerate slow VM/IO.
    ShutdownAppWaitMilliseconds = 3000
    ShutdownHandlerBudgetMilliseconds = 4500
    ShutdownReserveMilliseconds = 1000

    # During OS session ending, safety beats log archive.
    ShutdownSkipPostActions = $true

    NormalExitOutputDrainMilliseconds = 10000
    NormalExitOutputQuietMilliseconds = 250
    NormalExitClosePseudoConsoleBeforeDrain = $true

    PostActions = @(
        @{
            Name = "vaultwarden exit code is zero"
            Type = "ExitCodeEquals"
            ExpectedExitCode = 0
            TreatFailureAsError = $false
        },
        @{
            Name = "archive vaultwarden log on normal exit"
            Type = "CustomPowerShell"
            TreatFailureAsError = $false
            ScriptBlock = {
                param($Config, $Result, $CapturedOutput)

                # Derive vaultwarden's own log directory from ENV_FILE to avoid relying on
                # outer config-script local variables being available at invocation time.
                $envFile = $Config.EnvironmentVariables["ENV_FILE"]
                if ([string]::IsNullOrWhiteSpace([string]$envFile)) {
                    return @{
                        Success = $false
                        Message = "ENV_FILE is not configured; cannot locate vaultwarden log directory"
                    }
                }

                $appDataDir = Split-Path -Parent ([string]$envFile)
                $vaultwardenLogDir = Join-Path $appDataDir "logs"
                $currentLog = Join-Path $vaultwardenLogDir "vaultwarden.log"

                if (-not (Test-Path -LiteralPath $currentLog -PathType Leaf)) {
                    return @{
                        Success = $true
                        Message = "vaultwarden.log not found; archive skipped"
                    }
                }

                try {
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $archivedLog = Join-Path $vaultwardenLogDir "vaultwarden_$timestamp.log"
                    Move-Item -Path $currentLog -Destination $archivedLog -Force

                    $maxLogFiles = 30
                    $oldLogs = Get-ChildItem -Path $vaultwardenLogDir -Filter "vaultwarden_*.log" |
                        Sort-Object LastWriteTime -Descending

                    if ($oldLogs.Count -gt $maxLogFiles) {
                        $oldLogs |
                            Select-Object -Skip $maxLogFiles |
                            Remove-Item -Force
                    }

                    return @{
                        Success = $true
                        Message = "Archived vaultwarden log: $archivedLog"
                    }
                }
                catch {
                    return @{
                        Success = $false
                        Message = "Failed to archive vaultwarden log: $_"
                    }
                }
            }
        }
    )
}
