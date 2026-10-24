@echo off
rem eraBACK update launcher. Copies the updater to TEMP so that it can replace its own files safely.
rem Keep this file as simple as possible: the updater never overwrites it while running.
chcp 65001 >nul
setlocal
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
if not exist "%ROOT%\_update\update.ps1" (
  echo _update\update.ps1 was not found.
  pause
  exit /b 1
)
copy /y "%ROOT%\_update\update.ps1" "%TEMP%\eraBACK_update.ps1" >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\eraBACK_update.ps1" -Root "%ROOT%" %*
echo.
pause
