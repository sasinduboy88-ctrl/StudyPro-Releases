@echo off
setlocal
title StudyPro Auto-Update Setup
set "SETUP_SCRIPT=%TEMP%\StudyPro-AutoUpdate-Setup.ps1"
echo.
echo Downloading the official StudyPro setup helper...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/sasinduboy88-ctrl/StudyPro-Releases/main/setup/Setup-StudyPro-AutoUpdate.ps1' -OutFile $env:TEMP\StudyPro-AutoUpdate-Setup.ps1"
if errorlevel 1 (
  echo.
  echo Could not download the official setup helper. Check your internet connection and try again.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SETUP_SCRIPT%"
if errorlevel 1 (
  echo.
  echo Setup stopped. Read the message above.
) else (
  echo.
  echo StudyPro auto-update setup completed.
)
pause
endlocal
