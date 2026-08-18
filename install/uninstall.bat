@echo off
setlocal
set "DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%register-menus.ps1" -Action uninstall -InstallDir "%DIR:~0,-1%"
echo.
echo Контекстные меню DinaPlayer удалены.
pause
