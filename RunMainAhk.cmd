@echo off
if not exist "%~dp0runtime\AutoHotkey64.exe" (
    echo AutoHotkey64.exe is missing from the runtime folder.
    pause
    exit /b 1
)
start "" "%~dp0runtime\AutoHotkey64.exe" "%~dp0Main.ahk"
