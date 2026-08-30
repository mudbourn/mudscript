@echo off
REM Build ms_gc_read.exe — the Windows gamepad reader for mudscript.
REM
REM Requires SDL2 development libraries and MSVC (Developer Command Prompt) or
REM MinGW-w64. Set SDL2_DIR to your SDL2 dev root (the folder containing
REM include\SDL.h and lib\x64\), or drop SDL2 next to this script as .\SDL2.
REM
REM Usage:  build.bat            (auto-detects cl.exe, falls back to gcc)
REM
REM The resulting ms_gc_read.exe + SDL2.dll must sit on the host's PATH (the
REM mudscript host launches "ms_gc_read"). SDL2.dll ships next to the exe.

setlocal
if "%SDL2_DIR%"=="" set SDL2_DIR=%~dp0SDL2

set INC=%SDL2_DIR%\include
set LIB=%SDL2_DIR%\lib\x64

if not exist "%INC%\SDL.h" (
  echo ERROR: SDL.h not found under "%INC%".
  echo Set SDL2_DIR to your SDL2 development root and retry.
  exit /b 1
)

where cl.exe >nul 2>nul
if %ERRORLEVEL%==0 (
  echo Building with MSVC...
  cl /O2 /nologo "%~dp0ms_gc_read.c" /I "%INC%" /Fe:"%~dp0ms_gc_read.exe" ^
     /link /LIBPATH:"%LIB%" SDL2.lib SDL2main.lib shell32.lib /SUBSYSTEM:CONSOLE
  goto :copydll
)

where gcc.exe >nul 2>nul
if %ERRORLEVEL%==0 (
  echo Building with MinGW gcc...
  gcc -O2 -Wall "%~dp0ms_gc_read.c" -I "%INC%" -L "%LIB%" ^
      -o "%~dp0ms_gc_read.exe" -lmingw32 -lSDL2main -lSDL2
  goto :copydll
)

echo ERROR: neither cl.exe nor gcc.exe found on PATH.
exit /b 1

:copydll
if exist "%LIB%\SDL2.dll" copy /Y "%LIB%\SDL2.dll" "%~dp0SDL2.dll" >nul
echo Done: %~dp0ms_gc_read.exe
endlocal
