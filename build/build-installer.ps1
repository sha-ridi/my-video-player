# Builds dist/DinaPlayer-Setup.exe — a small installer/updater that downloads the
# latest player from the public releases repo (GitHub Releases) at runtime.
# Compiled with the in-box .NET Framework C# compiler (present on every Windows),
# so the resulting exe needs no runtime install on the target PC.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "C# compiler not found: $csc" }

$out  = Join-Path $repo 'dist/DinaPlayer-Setup.exe'
$icon = Join-Path $repo 'assets/dinasetup.ico'  # player face + wrench badge
$src1 = Join-Path $repo 'installer/DinaSetup.cs'
$src2 = Join-Path $repo 'installer/DinaSetupForm.cs'
# Embedded assets: Inter font + the app icon (dinaplayer.ico) shown in the window
# header, so it looks the same on any PC (no system font install needed).
# Referenced by manifest name in code. ($icon above is the exe's own /win32icon.)
$font = Join-Path $repo 'portable_config/fonts/Inter.ttf'
$hdricon = Join-Path $repo 'assets/dinaplayer.ico'
# DPI-awareness manifest -> crisp window at 125%/150%/… display scaling.
$manifest = Join-Path $repo 'installer/app.manifest'
New-Item -ItemType Directory -Force -Path (Split-Path $out -Parent) | Out-Null
Remove-Item $out -Force -ErrorAction SilentlyContinue

& $csc /nologo /target:winexe /codepage:65001 /optimize+ "/out:$out" "/win32icon:$icon" `
    "/win32manifest:$manifest" `
    /reference:System.dll /reference:System.Windows.Forms.dll /reference:System.Drawing.dll `
    /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll `
    "/resource:$font,Inter.ttf" "/resource:$hdricon,dinaicon.ico" `
    $src1 $src2
if ($LASTEXITCODE -ne 0) { throw "csc failed with exit code $LASTEXITCODE" }

Write-Host ("Built {0} ({1:N0} KB)" -f $out, ((Get-Item $out).Length / 1KB))
