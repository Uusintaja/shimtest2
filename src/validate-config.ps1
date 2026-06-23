<#
.SYNOPSIS
    Small utility to validate a wrapper config file and print merged config JSON.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\src\validate-config.ps1 -ConfigPath .\configs\sample.stdown.ps1
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "common.ps1")

$userConfig = . $ConfigPath
$config = Merge-WrapperConfig -UserConfig $userConfig
Assert-WrapperConfig -Config $config | Out-Null
Initialize-WrapperDirectories -Config $config

Write-Host "Config is valid. Merged config:"
ConvertTo-WrapperJson -InputObject $config -Depth 8
