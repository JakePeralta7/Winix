@echo off
setlocal enabledelayedexpansion

echo Running unit tests...
for %%P in (cliflag winconsole winpath) do (
    echo   tests\%%P
    odin test tests\%%P
    if errorlevel 1 (
        echo Unit tests failed: %%P
        exit /b 1
    )
)

echo Building binaries...
call .\build.bat
if errorlevel 1 exit /b 1

echo Running integration tests...
odin test tests\pwd_integration
if errorlevel 1 (
    echo Integration tests failed
    exit /b 1
)

echo All tests passed.
endlocal
