@echo off
setlocal

set "LOGS=%LOCALAPPDATA%\Roblox\logs"
set "CACHE=%LOCALAPPDATA%\Roblox\rbx-storage"

if exist "%LOGS%" (
    del /q "%LOGS%\*microprofile*.html" 2>nul
    forfiles /p "%LOGS%" /m *.log /d -3 /c "cmd /c del @path" 2>nul
)

if exist "%CACHE%" (
    rd /s /q "%CACHE%" 2>nul
)

endlocal
