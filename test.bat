@echo off
setlocal enabledelayedexpansion

echo Running unit tests...
for %%P in (cliflag winconsole pwd_unit) do (
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
for %%P in (pwd_integration ls_integration rm_integration cat_integration which_integration pkill_integration) do (
    echo   tests\%%P
    odin test tests\%%P
    if errorlevel 1 (
        echo Integration tests failed: %%P
        exit /b 1
    )
)

echo All tests passed.
endlocal
