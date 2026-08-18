param(
    [ValidateSet('install','uninstall')][string]$Action = 'install',
    [string]$InstallDir = $PSScriptRoot
)
$ErrorActionPreference = 'Stop'
$exe    = Join-Path $InstallDir 'DinaPlayer.exe'
$folder = Join-Path $InstallDir 'play-folder.ps1'
$exts   = '.mkv','.mp4','.avi','.mov','.webm','.m4v','.ts','.flv','.wmv','.mpg','.mpeg'
$classes = 'HKCU:\Software\Classes'

function Set-Menu($keyPath, $label, $command, $icon) {
    New-Item -Path $keyPath -Force | Out-Null
    Set-ItemProperty -Path $keyPath -Name '(default)' -Value $label
    Set-ItemProperty -Path $keyPath -Name 'Icon' -Value $icon
    $cmd = Join-Path $keyPath 'command'
    New-Item -Path $cmd -Force | Out-Null
    Set-ItemProperty -Path $cmd -Name '(default)' -Value $command
}

if ($Action -eq 'install') {
    # File right-click: "Play with DinaPlayer" (matches the installer's label)
    foreach ($ext in $exts) {
        $key = "$classes\SystemFileAssociations\$ext\shell\DinaPlayer"
        Set-Menu $key 'Play with DinaPlayer' "`"$exe`" `"%1`"" "$exe,0"
    }
    # Folder right-click (folder icon): "Play with DinaPlayer"
    $fcmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$folder`" `"%V`""
    Set-Menu "$classes\Directory\shell\DinaPlayer" 'Play with DinaPlayer' $fcmd "$exe,0"
    # Folder BACKGROUND right-click (empty space inside an open folder)
    Set-Menu "$classes\Directory\Background\shell\DinaPlayer" 'Play with DinaPlayer' $fcmd "$exe,0"
    Write-Host 'DinaPlayer context menus installed (HKCU).'
}
else {
    foreach ($ext in $exts) {
        Remove-Item "$classes\SystemFileAssociations\$ext\shell\DinaPlayer" -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item "$classes\Directory\shell\DinaPlayer" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$classes\Directory\Background\shell\DinaPlayer" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'DinaPlayer context menus removed.'
}
