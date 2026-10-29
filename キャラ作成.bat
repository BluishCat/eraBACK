@echo off
rem eraBACK character tool launcher. Starts a small local server (127.0.0.1 only) and opens the tool in the browser.
rem Keep this file ASCII only, like the updater launcher.
chcp 65001 >nul
setlocal
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
if not exist "%ROOT%\_chara_tool\server.ps1" (
  echo _chara_tool\server.ps1 was not found.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\_chara_tool\server.ps1" -Root "%ROOT%" %*
echo.
pause
