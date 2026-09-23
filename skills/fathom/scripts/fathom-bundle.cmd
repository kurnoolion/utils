@echo off
rem Fathom bundle launcher - double-click, or run with arguments:
rem   fathom-bundle.cmd "D:\mail-export;D:\rf-team" "upper C-band filter decision" 2026-01
setlocal
set "HERE=%~dp0"
set "PATHS=%~1"
set "QUERY=%~2"
set "SINCE=%~3"
if not defined PATHS set /p "PATHS=Folders to search, separated by semicolons: "
if not defined QUERY set /p "QUERY=Your question, as a few key terms: "
if not defined SINCE set /p "SINCE=Only documents since yyyy-MM, or blank for all: "
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%fathom-bundle.ps1" -Paths "%PATHS%" -Query "%QUERY%" -Since "%SINCE%"
echo.
pause
