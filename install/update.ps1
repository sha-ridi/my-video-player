# DinaPlayer — обновление установленной версии.
# Положи новый DinaPlayer-Portable.zip рядом с этим файлом и запусти update.bat.
# Файлы плеера и конфиги обновляются ПОВЕРХ текущей папки; прогресс просмотра и
# настройки (watch_later, pause-on-start) сохраняются.
$ErrorActionPreference = 'Stop'
# Корректный вывод кириллицы в консоли независимо от локали системы.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$dir = $PSScriptRoot
$zip = Join-Path $dir 'DinaPlayer-Portable.zip'

if (-not (Test-Path $zip)) {
    Write-Host ''
    Write-Host 'Не найден DinaPlayer-Portable.zip рядом с этим файлом.'
    Write-Host 'Положи новый архив в эту папку и запусти снова:'
    Write-Host ('  ' + $dir)
    return
}

if (Get-Process -Name DinaPlayer -ErrorAction SilentlyContinue) {
    Write-Host ''
    Write-Host 'DinaPlayer сейчас запущен. Закрой плеер и запусти обновление снова.'
    return
}

$tmp = Join-Path $env:TEMP ('dina-update-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    Write-Host 'Распаковываю новую версию...'
    Expand-Archive -Path $zip -DestinationPath $tmp -Force

    Write-Host 'Обновляю файлы плеера...'
    # update.bat не трогаем — он выполняется прямо сейчас.
    foreach ($item in 'DinaPlayer.exe', 'mpv.com', 'mpv', 'setup.bat', 'uninstall.bat',
                      'register-menus.ps1', 'play-folder.ps1', 'update.ps1') {
        $src = Join-Path $tmp $item
        if (Test-Path $src) { Copy-Item $src $dir -Recurse -Force }
    }

    Write-Host 'Обновляю конфиги (прогресс и настройки сохраняю)...'
    $cfgSrc = Join-Path $tmp 'portable_config'
    $cfgDst = Join-Path $dir 'portable_config'
    if (Test-Path $cfgSrc) {
        robocopy $cfgSrc $cfgDst /MIR /XD watch_later cache /XF pause-on-start.state fullscreen-on-start.state /NFL /NDL /NJH /NJS /NC /NS | Out-Null
    }

    Write-Host ''
    Write-Host 'Готово! DinaPlayer обновлён. Прогресс просмотра и настройки сохранены.'
    Write-Host '(setup.bat заново запускать не нужно — путь к плееру не изменился.)'
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
