$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force -Path bin | Out-Null

Get-ChildItem cmd -Directory | ForEach-Object {
    $name = $_.Name
    Write-Host "Building $name..."
    odin build $_.FullName "-out:bin\$name.exe" "-o:size" "-extra-linker-flags:/OPT:REF,ICF"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed for $name"
        exit $LASTEXITCODE
    }
}

Write-Host "All binaries built into .\bin\"
