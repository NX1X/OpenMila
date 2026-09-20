# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Puts the current PowerShell session into a Visual Studio developer
# environment. Swift on Windows compiles and links through the MSVC toolchain
# and the Windows SDK, so without this `swift build` reports
# "unable to load standard library for target x86_64-unknown-windows-msvc".
#
# Dot-source it:  . scripts\port\vsdev.ps1
$ErrorActionPreference = "Stop"

if ($env:VSCMD_VER) { return }  # already inside a developer environment

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
