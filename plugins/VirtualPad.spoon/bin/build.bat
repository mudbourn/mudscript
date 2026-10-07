@echo off
setlocal

where gcc.exe >nul 2>nul
if %ERRORLEVEL%==0 goto :build

for %%D in ("C:\msys64\mingw64\bin" "C:\msys64\ucrt64\bin" "C:\mingw64\bin" "C:\TDM-GCC-64\bin") do (
    if exist "%%~D\gcc.exe" set "PATH=%%~D;%PATH%" & goto :build
)

call :winlibs
if defined GCC_DIR goto :build

echo gcc not found, installing WinLibs MinGW with winget
winget install --id BrechtSanders.WinLibs.POSIX.UCRT -e --silent --accept-package-agreements --accept-source-agreements
call :winlibs
if defined GCC_DIR goto :build

echo ERROR: could not find or install gcc
exit /b 1

:winlibs
for /d %%P in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\BrechtSanders.WinLibs*") do (
    if exist "%%~P\mingw64\bin\gcc.exe" (
        set "GCC_DIR=%%~P\mingw64\bin"
        set "PATH=%%~P\mingw64\bin;%PATH%"
    )
)
exit /b 0

:build
gcc -O2 -Wall -static -o "%~dp0ms_vpad.exe" "%~dp0ms_vpad.c" -lsetupapi
if errorlevel 1 exit /b 1
echo Built %~dp0ms_vpad.exe
