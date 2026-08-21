@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
set "RC=%ERRORLEVEL%"

if "%RC%"=="20" (
  echo.
  echo Windows restart required.
  echo Restart Windows and run build.cmd again.
  pause
  exit /b 0
)

if not "%RC%"=="0" (
  echo.
  echo build.ps1 failed with exit code %RC%.
  pause
)

exit /b %RC%
