# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Puts the current PowerShell session into a Visual Studio developer
# environment. Swift on Windows compiles and links through the MSVC toolchain
# and the Windows SDK, so without this `swift build` reports
# "unable to load standard library for target x86_64-unknown-windows-msvc".
#
# Dot-source it:  . scripts\port\vsdev.ps1
$ErrorActionPreference = "Stop"

function Set-SwiftEnvironment {
    # Swift on Windows finds its standard library through SDKROOT. The
    # installer sets it machine-wide, but a toolchain restored from a CI cache
    # never ran the installer, and a fresh install does not reach a shell that
    # is already running: both end in "unable to load standard library for
    # target x86_64-unknown-windows-msvc". Deriving it from swift.exe works in
    # every case.
    $swift = (Get-Command swift -ErrorAction SilentlyContinue)
    if (-not $swift) { return }
    # ...\Programs\Swift\Toolchains\<version>\usr\bin\swift.exe
    $swiftRoot = Split-Path (Split-Path (Split-Path (Split-Path (Split-Path $swift.Source -Parent) -Parent) -Parent) -Parent) -Parent
    $sdk = Join-Path $swiftRoot "Platforms\Windows.platform\Developer\SDKs\Windows.sdk"
    if (Test-Path $sdk) {
        $env:SDKROOT = $sdk
        Write-Host "SDKROOT: $sdk"
    } else {
        Write-Warning "no Windows.sdk under $swiftRoot; swift build will not find the standard library"
    }
    $runtimes = Join-Path $swiftRoot "Runtimes"
    if (Test-Path $runtimes) {
        Get-ChildItem $runtimes -Directory | ForEach-Object {
            $bin = Join-Path $_.FullName "usr\bin"
            if ((Test-Path $bin) -and ($env:Path -notlike "*$bin*")) { $env:Path = "$bin;$env:Path" }
        }
    }
}

if ($env:VSCMD_VER) { Set-SwiftEnvironment; return }  # already in a developer environment

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere.exe not found; is Visual Studio installed?" }

$install = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
if (-not $install) { throw "no Visual Studio installation with the C++ tools was found" }

$devShell = Join-Path $install "Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
if (-not (Test-Path $devShell)) { throw "developer shell module not found at $devShell" }

Import-Module $devShell
Enter-VsDevShell -VsInstallPath $install -SkipAutomaticLocation `
    -DevCmdArguments "-arch=x64 -host_arch=x64" | Out-Null
Write-Host "Visual Studio environment: $env:VSCMD_VER ($install)"
Set-SwiftEnvironment
