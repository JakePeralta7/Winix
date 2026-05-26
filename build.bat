@echo off
setlocal enabledelayedexpansion

REM Locate odin: prefer PATH, fall back to known dev location.
set ODIN=odin
where %ODIN% >nul 2>nul
if errorlevel 1 (
    set ODIN=C:\Users\ellevi\Downloads\odin-windows-amd64-dev-2026-05\dist\odin.exe
)

if not exist bin mkdir bin

for /d %%D in (cmd\*) do (
    echo Building %%~nxD...
    "%ODIN%" build %%D -out:bin\%%~nxD.exe -o:speed
    if errorlevel 1 (
        echo Build failed for %%~nxD
        exit /b 1
    )
)

echo All binaries built into .\bin\
endlocal
