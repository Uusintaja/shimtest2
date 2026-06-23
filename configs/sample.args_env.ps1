$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WorkRoot = Join-Path $ProjectRoot "work\args_env"
$LogRoot = Join-Path $ProjectRoot "logs"

return @{
    AppPath = Join-Path $ProjectRoot "bin\args_env.exe"
    AppArgs = @("alpha", "two words", "quote-value", "proxy=127.0.0.1:8080")
    WorkingDirectory = $WorkRoot
    EnvironmentVariables = @{
        APP_CONFIG_PATH = $WorkRoot
        WRAPPER_TEST_ENV1 = "value-one"
        WRAPPER_TEST_PROXY = "127.0.0.1:8080"
    }
    LogEnvironmentVariableValues = $false
    CreateDirectories = @($WorkRoot, $LogRoot)
    LogFilePath = Join-Path $LogRoot "wrapper.args_env.log"
    AppOutputLogFilePath = Join-Path $LogRoot "app.args_env.output.log"
    OutputEncoding = "utf-8"
    StripAnsiSequences = $true
    InputMode = "None"
    EnableShutdownSentinel = $true
    PostActions = @(
        @{ Name="argc=5 with four custom args plus program name"; Type="RegexOutputContains"; Pattern="argc=5"; TreatFailureAsError=$true },
        @{ Name="arg with spaces received"; Type="RegexOutputContains"; Pattern="argv\[2\]=two words"; TreatFailureAsError=$true },
        @{ Name="APP_CONFIG_PATH injected"; Type="RegexOutputContains"; Pattern="env:APP_CONFIG_PATH="; TreatFailureAsError=$true },
        @{ Name="WRAPPER_TEST_ENV1 injected"; Type="RegexOutputContains"; Pattern="env:WRAPPER_TEST_ENV1=value-one"; TreatFailureAsError=$true },
        @{ Name="WRAPPER_TEST_PROXY injected"; Type="RegexOutputContains"; Pattern="env:WRAPPER_TEST_PROXY=127\.0\.0\.1:8080"; TreatFailureAsError=$true },
        @{ Name="USERPROFILE inherited"; Type="RegexOutputContains"; Pattern="env:USERPROFILE="; TreatFailureAsError=$true }
    )
}
