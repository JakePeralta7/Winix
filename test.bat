@echo off
setlocal enabledelayedexpansion

REM Locate odin: prefer PATH, fall back to known dev location.
set ODIN=odin
where %ODIN% >nul 2>nul
if errorlevel 1 (
    set ODIN=C:\Users\ellevi\Downloads\odin-windows-amd64-dev-2026-05\dist\odin.exe
)

echo Running unit tests...
for %%P in (cliflag winconsole winpath) do (
    echo   tests\%%P
    "%ODIN%" test tests\%%P
    if errorlevel 1 (
        echo Unit tests failed: %%P
        exit /b 1
    )
)

echo Building binaries...
call .\build.bat
if errorlevel 1 exit /b 1

echo Running integration tests...
"%ODIN%" test tests\pwd_integration
if errorlevel 1 (
    echo Integration tests failed
    exit /b 1
)

echo All tests passed.
endlocal
