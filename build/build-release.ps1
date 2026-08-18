$ErrorActionPreference = 'Stop'
$repo  = Split-Path $PSScriptRoot -Parent
$stage = Join-Path $repo 'build/tmp/stage'
$dist  = Join-Path $repo 'dist'
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage,$dist | Out-Null

# 1. mpv into stage root.
& (Join-Path $PSScriptRoot 'fetch-mpv.ps1') -Dest $stage

# 2. Trim mpv extras we do not ship (incl. mpv's own file-association scripts,
#    which would register "mpv" instead of DinaPlayer and confuse users).
foreach ($junk in 'installer','doc','updater.bat','update*.bat',
                  'mpv-install.bat','mpv-uninstall.bat','mpv-register.bat','mpv-unregister.bat') {
    Get-ChildItem -Path $stage -Filter $junk -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# 3. Rename mpv.exe -> DinaPlayer.exe + set icon.
& (Join-Path $PSScriptRoot 'apply-branding.ps1') -TargetDir $stage

# 4. portable_config (exclude runtime junk).
Copy-Item (Join-Path $repo 'portable_config') $stage -Recurse
Remove-Item (Join-Path $stage 'portable_config/watch_later') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $stage 'portable_config/pause-on-start.state') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $stage 'portable_config/volume.state') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $stage 'portable_config/fullscreen-on-start.state') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $stage 'portable_config/skip-opening.state') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $stage 'portable_config/skip-ending.state') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $stage 'portable_config/track-prefs.state') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $stage 'portable_config/last-file.state') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $stage 'portable_config/sub-seek-target.state') -Force -ErrorAction SilentlyContinue
# cache holds the shader cache and the per-user watched/in-progress lists — never
# ship it (mpv recreates it; bundling would clobber the user's data on update).
Remove-Item (Join-Path $stage 'portable_config/cache') -Recurse -Force -ErrorAction SilentlyContinue

# 5. Install scripts at the ZIP root (next to DinaPlayer.exe).
#    README.md is a dev-only doc — not shipped in the release.
Copy-Item (Join-Path $repo 'install/*') $stage -Force

# Strip .gitkeep placeholders wherever they landed in the stage (e.g. install/.gitkeep).
Get-ChildItem $stage -Recurse -Filter '.gitkeep' -Force | Remove-Item -Force

# 5.4 Licensing: the license texts and third-party notices must travel with the
#     distributed binaries (GPL/LGPL/MPL require it). The DinaPlayer scripts and
#     configs themselves ship as source under portable_config/; mpv's source is
#     linked from THIRD-PARTY.md.
Copy-Item (Join-Path $repo 'LICENSE')        $stage -Force
Copy-Item (Join-Path $repo 'THIRD-PARTY.md') $stage -Force
Copy-Item (Join-Path $repo 'licenses')       $stage -Recurse -Force

# 5.5 Bundle the installer inside the ZIP so a normal update drops a fresh
#     DinaPlayer-Setup.exe next to the player — this makes the in-player
#     "update" button work (it launches that copy) even for installs that
#     never had one, and keeps it up to date. The updater skips overwriting
#     its own running exe (see DinaSetup.CopyDir), so this is safe.
& (Join-Path $PSScriptRoot 'build-installer.ps1')
$setupExe = Join-Path $dist 'DinaPlayer-Setup.exe'
if (-not (Test-Path $setupExe)) { throw "Setup.exe не собрался: $setupExe" }
Copy-Item $setupExe (Join-Path $stage 'DinaPlayer-Setup.exe') -Force

# 6. Sanity check required files.
$required = 'DinaPlayer.exe','portable_config/mpv.conf','portable_config/input.conf',
           'portable_config/scripts/uosc/main.lua','portable_config/scripts/thumbfast.lua',
           'portable_config/scripts/autoload.lua','portable_config/fonts/uosc_icons.otf',
           'setup.bat','uninstall.bat',
           'register-menus.ps1','play-folder.ps1',
           'LICENSE','THIRD-PARTY.md','licenses/GPL-3.0.txt','licenses/LGPL-2.1.txt',
           'licenses/MPL-2.0.txt','licenses/OFL-1.1.txt'
foreach ($f in $required) {
    if (-not (Test-Path (Join-Path $stage $f))) { throw "Release is missing: $f" }
}

# 7. Zip it.
$zip = Join-Path $dist 'DinaPlayer-Portable.zip'
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
Write-Host "Built $zip"
