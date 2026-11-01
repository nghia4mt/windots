@echo off
rem ---------------------------------------------------------------------------
rem  Debloat Windows 11 with PowerShell 7.
rem
rem  Double-click this file (or run it from cmd). It:
rem    - finds pwsh (PowerShell 7),
rem    - asks for administrator rights when needed,
rem    - keeps the window open so errors stay visible.
rem
rem  Examples:
rem    debloat.cmd -DryRun
rem    debloat.cmd -All
rem    debloat.cmd -RemoveEdge
rem ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"

set "SCRIPT=%~dp0debloat-app.ps1"
set "SCRIPTARGS=%*"
set "PWSH="

rem Prefer an absolute pwsh path; the WindowsApps alias works too.
for /f "delims=" %%i in ('where pwsh 2^>nul') do (
    if not defined PWSH set "PWSH=%%i"
)
if not defined PWSH if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PWSH if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" set "PWSH=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"

if not defined PWSH (
    echo [ERROR] PowerShell 7 ^(pwsh^) was not found.
    echo Install it from https://aka.ms/powershell and try again.
    echo.
    pause
    exit /b 1
)

if not exist "%SCRIPT%" (
    echo [ERROR] debloat-app.ps1 was not found next to this file.
    echo.
    pause
    exit /b 1
)

set "ELEVATED="
whoami /groups 2>nul | findstr /c:"S-1-16-12288" >nul && set "ELEVATED=1"
whoami /groups 2>nul | findstr /c:"S-1-16-16384" >nul && set "ELEVATED=1"

if not defined ELEVATED (
    echo Requesting administrator rights...
    "%PWSH%" -NoProfile -ExecutionPolicy Bypass -Command "$a = @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File',$env:SCRIPT); if ($env:SCRIPTARGS) { $a += ($env:SCRIPTARGS -split ' +') }; Start-Process -FilePath $env:PWSH -Verb RunAs -ArgumentList $a"
    exit /b
)

"%PWSH%" -NoExit -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
