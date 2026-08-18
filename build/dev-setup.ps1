$ErrorActionPreference = 'Stop'
$repo   = Split-Path $PSScriptRoot -Parent
$mpvDir = Join-Path $repo 'build/vendor/mpv'

if (-not (Test-Path (Join-Path $mpvDir 'mpv.exe'))) {
    & (Join-Path $PSScriptRoot 'fetch-mpv.ps1') -Dest $mpvDir
}

$link   = Join-Path $mpvDir 'portable_config'
$target = Join-Path $repo 'portable_config'
if (Test-Path $link) {
    $item = Get-Item $link -Force
    if ($item.LinkType -eq 'Junction') {
        # rmdir (non-recursive) removes only the reparse point, never the target contents
        cmd /c rmdir "$link" | Out-Null
    } else {
        Remove-Item $link -Recurse -Force
    }
}
New-Item -ItemType Junction -Path $link -Target $target | Out-Null

Write-Host "Dev sandbox ready. Test with: `"$mpvDir\mpv.exe`" <video-file>"
