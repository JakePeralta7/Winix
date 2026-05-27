$ErrorActionPreference = 'Stop'

Write-Host "Running unit tests..."
foreach ($p in @('cliflag', 'winconsole', 'winpath')) {
    Write-Host "  tests/$p"
    odin test "tests/$p"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Unit tests failed: $p"
        exit $LASTEXITCODE
    }
}

Write-Host "Building binaries..."
& powershell -ExecutionPolicy Bypass -File ./build.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Running integration tests..."
foreach ($pkg in @('pwd_integration', 'ls_integration')) {
    Write-Host "  tests/$pkg"
    odin test "tests/$pkg"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Integration tests failed: $pkg"
        exit $LASTEXITCODE
    }
}

Write-Host "All tests passed."
