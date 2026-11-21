@echo off
(
    if exist "%~dp0CheckRelease.ps1" (
        "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0CheckRelease.ps1" -Gui
        if errorlevel 2 (
            echo The release update could not be recovered.
            exit /b 2
        )
    )
    if not exist "%~dp0runtime\AutoHotkey64.exe" (
        "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0CheckRelease.ps1" -Gui -EnsureRuntime
    )
    if not exist "%~dp0runtime\AutoHotkey64.exe" (
        echo AutoHotkey64.exe could not be downloaded. Check your connection and try again.
        exit /b 1
    )
    start "" "%~dp0runtime\AutoHotkey64.exe" "%~dp0Main.ahk"
)
