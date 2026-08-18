# Publishes a new player build to the public releases repo (GitHub Releases),
# from where DinaPlayer-Setup.exe downloads it. Requires GitHub CLI (gh):
#   winget install GitHub.cli   (once)
#   gh auth login               (once)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$releaseRepo = 'sha-ridi/my-video-player'

# 1. Build a fresh portable ZIP (build-release.ps1 also builds the installer and
#    bundles it inside the ZIP). Publish Setup.exe as an asset too, so the
#    in-player update can refresh the bundled copy -> installer fixes propagate.
& (Join-Path $PSScriptRoot 'build-release.ps1')
$zip = Join-Path $repo 'dist/DinaPlayer-Portable.zip'
if (-not (Test-Path $zip)) { throw "ZIP не собрался: $zip" }
$setup = Join-Path $repo 'dist/DinaPlayer-Setup.exe'
if (-not (Test-Path $setup)) { throw "Setup.exe не собрался: $setup" }

# 2. Locate GitHub CLI (may not be on PATH in a shell opened right after install).
$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $gh) {
    $cand = Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'
    if (Test-Path $cand) { $gh = $cand }
}
if (-not $gh) { throw "GitHub CLI (gh) не найден. Установи: winget install GitHub.cli, затем gh auth login." }

# 3. Unique, sortable version tag from the date.
$tag = 'v' + (Get-Date -Format 'yyyy.MM.dd.HHmm')

# 4. Create the release with the ZIP as an asset (asset keeps the fixed name so
#    the installer's .../releases/latest/download/DinaPlayer-Portable.zip works).
& $gh release create $tag $zip $setup --repo $releaseRepo --title $tag --notes "DinaPlayer $tag"
if ($LASTEXITCODE -ne 0) { throw "gh release create failed ($LASTEXITCODE)" }

Write-Host ""
Write-Host "Опубликован релиз $tag -> $releaseRepo"
Write-Host "Загрузчик берёт: https://github.com/$releaseRepo/releases/latest/download/DinaPlayer-Portable.zip"
