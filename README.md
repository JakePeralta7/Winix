# Winix

Windows ports of classic Unix command-line tools, written in Odin, calling the Windows API directly.

## Build

Prerequisites: Odin compiler on `PATH`, Windows 10+, `windows_amd64`.

```cmd
build.bat
```

or

```powershell
.\build.ps1
```

Binaries land in `.\bin\`.

## Test

```cmd
test.bat
```

Runs unit tests for the internal packages, then builds, then runs integration tests against the built `bin\pwd.exe`.

## License

See `LICENSE`.
