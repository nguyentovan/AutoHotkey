@echo off
if not exist "%~dp0runtime\AutoHotkey64.exe" (
    echo AutoHotkey64.exe is missing from the runtime folder.
    pause
    exit /b 1
)
(
    if exist "%~dp0CheckRelease.ps1" (
        "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0CheckRelease.ps1"
        if errorlevel 2 (
            echo The release update could not be recovered.
            pause
            exit /b 2
        )
    )
    start "" "%~dp0runtime\AutoHotkey64.exe" "%~dp0Main.ahk"
)
