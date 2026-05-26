$ErrorActionPreference = 'Stop'

# Locate odin: prefer PATH, fall back to known dev location.
$odin = 'odin'
if (-not (Get-Command $odin -ErrorAction SilentlyContinue)) {
    $odin = 'C:\Users\ellevi\Downloads\odin-windows-amd64-dev-2026-05\dist\odin.exe'
}

Write-Host "Running unit tests..."
foreach ($p in @('cliflag', 'winconsole', 'winpath')) {
    Write-Host "  tests/$p"
    & $odin test "tests/$p"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Unit tests failed: $p"
        exit $LASTEXITCODE
    }
}

Write-Host "Building binaries..."
& powershell -ExecutionPolicy Bypass -File ./build.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Running integration tests..."
& $odin test tests/pwd_integration
if ($LASTEXITCODE -ne 0) {
    Write-Error "Integration tests failed"
    exit $LASTEXITCODE
}

Write-Host "All tests passed."
