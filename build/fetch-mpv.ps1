param(
    [Parameter(Mandatory = $true)][string]$Dest
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$tmp = Join-Path $env:TEMP 'dinaplayer-fetch'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# 1. Standalone 7-Zip extractor (can extract .7z, ~600 KB, no install).
$sevenzr = Join-Path $tmp '7zr.exe'
if (-not (Test-Path $sevenzr)) {
    Invoke-WebRequest 'https://www.7-zip.org/a/7zr.exe' -OutFile $sevenzr
}

# 2. Latest mpv Windows build (zhongfly ships mpv.exe + libmpv).
$headers = @{ 'User-Agent' = 'dinaplayer-build' }
$rel = Invoke-RestMethod 'https://api.github.com/repos/zhongfly/mpv-winbuild/releases/latest' -Headers $headers
$asset = $rel.assets |
    Where-Object { $_.name -like 'mpv-x86_64-*.7z' -and $_.name -notlike '*v3*' } |
    Select-Object -First 1
if (-not $asset) {
    $asset = $rel.assets | Where-Object { $_.name -like 'mpv-x86_64*.7z' } | Select-Object -First 1
}
if (-not $asset) { throw 'Could not find an mpv x86_64 .7z asset in the latest release.' }

$archive = Join-Path $tmp $asset.name
Write-Host "Downloading $($asset.name) ..."
Invoke-WebRequest $asset.browser_download_url -OutFile $archive

# 3. Extract into $Dest.
& $sevenzr x $archive "-o$Dest" -y | Out-Null
if (-not (Test-Path (Join-Path $Dest 'mpv.exe'))) {
    throw "mpv.exe not found in $Dest after extraction."
}
Write-Host "mpv extracted to $Dest"
