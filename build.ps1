$ErrorActionPreference = 'Stop'

# Locate odin: prefer PATH, fall back to known dev location.
$odin = 'odin'
if (-not (Get-Command $odin -ErrorAction SilentlyContinue)) {
    $odin = 'C:\Users\ellevi\Downloads\odin-windows-amd64-dev-2026-05\dist\odin.exe'
}

New-Item -ItemType Directory -Force -Path bin | Out-Null

Get-ChildItem cmd -Directory | ForEach-Object {
    $name = $_.Name
    Write-Host "Building $name..."
    & $odin build $_.FullName "-out:bin\$name.exe" "-o:speed"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed for $name"
        exit $LASTEXITCODE
    }
}

Write-Host "All binaries built into .\bin\"
