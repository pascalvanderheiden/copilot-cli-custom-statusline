@echo off
REM Windows wrapper for Copilot CLI custom statusline.
REM A .cmd wrapper is required on Windows: passing the interpreter, flags,
REM and script path inline in settings.json is unreliable (argument parsing
REM and stdin redirection both behave differently than on macOS/Linux).
REM
REM Uses pwsh (PowerShell 7) for clean UTF-8 handling. If you only have
REM Windows PowerShell 5.1, replace `pwsh` with `powershell.exe` below.

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0statusline.ps1"
