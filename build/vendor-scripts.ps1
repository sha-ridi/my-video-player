$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repo = Split-Path $PSScriptRoot -Parent
$pc   = Join-Path $repo 'portable_config'
$tmp  = Join-Path $env:TEMP 'dinaplayer-scripts'
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $tmp,"$pc/scripts","$pc/fonts","$pc/script-opts" | Out-Null

# --- uosc (release zip: scripts/uosc/**, fonts/*) ---
$uoscZip = Join-Path $tmp 'uosc.zip'
Invoke-WebRequest 'https://github.com/tomasklaen/uosc/releases/latest/download/uosc.zip' -OutFile $uoscZip
$uoscDir = Join-Path $tmp 'uosc'
Expand-Archive $uoscZip -DestinationPath $uoscDir -Force
Copy-Item (Join-Path $uoscDir 'scripts/uosc') (Join-Path $pc 'scripts') -Recurse -Force
# Copy whatever font files the release ships (current release: uosc_icons.otf +
# uosc_textures.ttf; older releases shipped a single uosc_icons.ttf) instead of
# hard-coding one filename, so this stays robust to upstream renames.
Copy-Item (Join-Path $uoscDir 'fonts/*') (Join-Path $pc 'fonts') -Force

# --- thumbfast (single lua file) ---
Invoke-WebRequest 'https://raw.githubusercontent.com/po5/thumbfast/master/thumbfast.lua' `
    -OutFile (Join-Path $pc 'scripts/thumbfast.lua')

# --- autoload (from mpv tools, has natural sort) ---
Invoke-WebRequest 'https://raw.githubusercontent.com/mpv-player/mpv/master/TOOLS/lua/autoload.lua' `
    -OutFile (Join-Path $pc 'scripts/autoload.lua')

Write-Host 'Vendored: uosc, thumbfast, autoload.'
