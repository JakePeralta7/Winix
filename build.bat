@echo off
setlocal enabledelayedexpansion

if not exist bin mkdir bin

for /d %%D in (cmd\*) do (
    echo Building %%~nxD...
    odin build %%D -out:bin\%%~nxD.exe -o:size -extra-linker-flags:"/OPT:REF,ICF"
    if errorlevel 1 (
        echo Build failed for %%~nxD
        exit /b 1
    )
)

echo All binaries built into .\bin\
endlocal
