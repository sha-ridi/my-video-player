param(
    [Parameter(Mandatory = $true)][string]$TargetDir  # folder containing mpv.exe
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repo = Split-Path $PSScriptRoot -Parent

$mpv = Join-Path $TargetDir 'mpv.exe'
$dina = Join-Path $TargetDir 'DinaPlayer.exe'
if (Test-Path $mpv) { Rename-Item $mpv 'DinaPlayer.exe' -Force }
if (-not (Test-Path $dina)) { throw "DinaPlayer.exe not found in $TargetDir" }

$rcedit = Join-Path $env:TEMP 'rcedit-x64.exe'
if (-not (Test-Path $rcedit)) {
    Invoke-WebRequest 'https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe' -OutFile $rcedit
}
& $rcedit $dina --set-icon (Join-Path $repo 'assets/dinaplayer.ico')
Write-Host "Branded: $dina"
