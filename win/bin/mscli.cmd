@echo off
setlocal EnableDelayedExpansion

set "HS_BIN="
for /f "delims=" %%i in ('where hs.cmd 2^>nul') do if not defined HS_BIN set "HS_BIN=%%i"
if not defined HS_BIN if defined MUDSPOON_ROOT if exist "%MUDSPOON_ROOT%\hs.cmd" set "HS_BIN=%MUDSPOON_ROOT%\hs.cmd"
set "UNINSTALL=HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F4C2D1A-6B3E-4C7A-9D52-3E1B7A0C94F6}_is1"
if not defined HS_BIN for /f "tokens=2,*" %%a in ('reg query "%UNINSTALL%" /v InstallLocation 2^>nul ^| findstr InstallLocation') do if exist "%%b\app\hs.cmd" set "HS_BIN=%%b\app\hs.cmd"

if not defined HS_BIN (
    echo The hs command was not found.
    echo Add the mudspoon folder to PATH or set MUDSPOON_ROOT.
    exit /b 1
)

set "LINE=%*"
if defined LINE set "LINE=!LINE:\=\\!"
if defined LINE set "LINE=!LINE:"=\\\"!"

set "OUT=%TEMP%\mscli_%RANDOM%%RANDOM%.out"
call "%HS_BIN%" -c "return ms.cli.run(\"!LINE!\")" > "%OUT%" 2>&1
if errorlevel 1 (
    del "%OUT%" >nul 2>&1
    echo Could not reach mudscript.
    echo Turn on Settings ^> Developer ^> Command Line Access, then reload.
    exit /b 1
)

type "%OUT%"
del "%OUT%" >nul 2>&1
exit /b 0
