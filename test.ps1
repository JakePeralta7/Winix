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
foreach ($pkg in @('pwd_integration', 'ls_integration', 'rm_integration', 'which_integration', 'pkill_integration')) {
    Write-Host "  tests/$pkg"
    if ($pkg -eq 'pkill_integration') {
        # pkill integration tests spawn/kill real processes and can interfere when run in parallel.
        odin test "tests/$pkg" -define:ODIN_TEST_THREADS=1
    } else {
        odin test "tests/$pkg"
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Integration tests failed: $pkg"
        exit $LASTEXITCODE
    }
}

Write-Host "All tests passed."
