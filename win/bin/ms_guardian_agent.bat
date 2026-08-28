@echo off
REM ms_guardian_agent.bat — mudscript OS-level Guardian (Windows)
REM
REM Runs as a scheduled task (triggered on ms_core.ahk file changes and at logon).
REM If the file's SHA-256 no longer matches the stored trusted hash,
REM AutoHotkey is killed and a notification is shown.
REM
REM This layer operates independently of the in-process check in init.ahk.
REM
REM Install with:  bin\install_guardian_agent.bat

setlocal enabledelayedexpansion

set "CORE=%~dp0..\ms_core_v2.ahk"
set "TRUST=%~dp0..\..\data\.ms_trusted_hash"
set "LOG=%LOCALAPPDATA%\mudscript\guardian_agent.log"

if not exist "%LOG%\" mkdir "%LOCALAPPDATA%\mudscript" 2>nul

echo [%date% %time%] Guardian triggered >> "%LOG%"

REM No trusted hash = uninitialized; nothing to enforce.
if not exist "%TRUST%" (
    echo [%date% %time%] No trusted hash on record -- skipping check. >> "%LOG%"
    exit /b 0
)

if not exist "%CORE%" (
    echo [%date% %time%] ms_core.ahk not found at %CORE% -- skipping check. >> "%LOG%"
    exit /b 0
)

REM Read trusted hash
set /p TRUSTED=<"%TRUST%"
if "!TRUSTED!"=="" (
    echo [%date% %time%] Empty trusted hash file. >> "%LOG%"
    exit /b 0
)

REM Compute current hash via PowerShell
for /f "usebackq delims=" %%a in (`
    powershell -NoProfile -Command "(Get-FileHash \"%CORE%\" -Algorithm SHA256).Hash.ToLower()"
`) do set "CURRENT=%%a"

if "!CURRENT!"=="" (
    echo [%date% %time%] Failed to hash ms_core.ahk. >> "%LOG%"
    exit /b 0
)

if "!CURRENT!"=="!TRUSTED!" (
    echo [%date% %time%] OK -- ms_core.ahk matches trusted hash (!CURRENT:~0,16!...). >> "%LOG%"
    exit /b 0
)

REM ── MISMATCH ──────────────────────────────────────────────────────────────
echo [%date% %time%] MISMATCH -- expected !TRUSTED:~0,16!... got !CURRENT:~0,16!... >> "%LOG%"

REM Kill AutoHotkey processes (both compiled EXE and interpreter)
taskkill /f /im AutoHotkey64.exe 2>nul
taskkill /f /im AutoHotkey32.exe 2>nul
taskkill /f /im AutoHotkey.exe 2>nul
REM Also kill any compiled ms_core exe
taskkill /f /im ms_core.exe 2>nul

REM Show a notification via PowerShell
powershell -NoProfile -Command ^
    "[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null;" ^
    "$notify = New-Object System.Windows.Forms.NotifyIcon;" ^
    "$notify.Icon = [System.Drawing.SystemIcons]::Warning;" ^
    "$notify.BalloonTipTitle = 'mudscript Guardian';" ^
    "$notify.BalloonTipText = 'Tamper Detected. ms_core.ahk hash mismatch.';" ^
    "$notify.BalloonTipIcon = 'Warning';" ^
    "$notify.Visible = $true;" ^
    "$notify.ShowBalloonTip(10000);" ^
    "Start-Sleep 10;" ^
    "$notify.Dispose()"

exit /b 1
