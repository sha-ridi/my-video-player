@echo off
setlocal
set "DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%register-menus.ps1" -Action install -InstallDir "%DIR:~0,-1%"
echo.
echo Готово. Правый клик по видео или папке -> DinaPlayer.
pause
