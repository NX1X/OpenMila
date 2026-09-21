# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Compiles the Windows installer with Inno Setup 6 from the payload
# packaging\windows\package.ps1 already staged for the portable zip. It builds
# nothing and stages nothing: if the stage is missing or incomplete it stops and
# says so, because an installer made from a half-staged payload looks fine and
# fails on the user's machine.
#
#   packaging\windows\build-installer.ps1 [-Version 1.9.5+port.0] [-Stage DIR] [-Iscc PATH]
param(
    [string]$Version,
    # The staged payload. Defaults to the stage package.ps1 writes for this
    # version, which is the whole point: one stage, two artifacts.
    [string]$Stage,
    # ISCC.exe, when it is somewhere this script would not look.
    [string]$Iscc
)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\common.ps1"

$root = Get-OpenMilaRoot -ScriptRoot $PSScriptRoot
$Version = Resolve-OpenMilaVersion -Root $root -Version $Version
if (-not $Stage) { $Stage = Get-OpenMilaStage -Root $root -Version $Version }
$out = Join-Path $root "dist"
$iss = Join-Path $PSScriptRoot "OpenMila.iss"

if (-not (Test-Path $Stage)) {
    throw "no staged payload at $Stage - run packaging\windows\package.ps1 -Prefix <whisper prefix> -Version $Version first"
}
# What the installer promises that the zip does not: a shortcut that starts the
# app, an icon in Installed Apps, and a .milaconfig association that opens
# something. Each of those names a file in the stage, so each is checked here
# rather than discovered by a user whose Start menu entry does nothing.
$required = @(
    "openmila.exe",          # the app: the shortcut and the association target
    "openmila-cli.exe",
    "openmila-mcp.exe",
    "openmila.ico",          # the Installed Apps and file-type icon
    "Foundation.dll",        # the Swift runtime travels with the payload
    "swiftCore.dll"
)
$missing = $required | Where-Object { -not (Test-Path (Join-Path $Stage $_)) }
if ($missing) {
    throw "the staged payload at $Stage is missing $($missing -join ', '): the installer would ship a broken install"
}

# ISCC.exe: an explicit path, then the environment, then PATH, then where the
# Chocolatey package and the vendor's own installer put it. Looking in the
# default location is what lets the release workflow install Inno Setup and call
# this script without wiring a path between the two steps.
$candidates = @()
if ($Iscc) { $candidates += $Iscc }
if ($env:ISCC) { $candidates += $env:ISCC }
$onPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if ($onPath) { $candidates += $onPath.Source }
foreach ($programs in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
    if ($programs) { $candidates += (Join-Path $programs "Inno Setup 6\ISCC.exe") }
}
$compiler = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $compiler) {
    throw "ISCC.exe not found. Install Inno Setup 6 (choco install innosetup --version 6.7.1), or pass -Iscc <path>"
}

New-Item -ItemType Directory -Force -Path $out | Out-Null
$base = "OpenMila-$Version-win64-setup"
$setup = Join-Path $out "$base.exe"
if (Test-Path $setup) { Remove-Item $setup }

$fileVersion = Get-OpenMilaFileVersion -Version $Version
Write-Host "Inno Setup: $compiler"
Write-Host "Stage:      $Stage"
Write-Host "Version:    $Version (resource $fileVersion)"

# /Qp keeps the output to progress and errors. Every path the .iss needs comes
# in as a define, so the script itself holds no machine-specific path.
& $compiler /Qp `
    "/DAppVersion=$Version" `
    "/DVersionInfo=$fileVersion" `
    "/DStageDir=$Stage" `
    "/DSourceRoot=$root" `
    "/DOutputDir=$out" `
    "/DOutputBase=$base" `
    $iss
if ($LASTEXITCODE -ne 0) { throw "ISCC.exe exited $LASTEXITCODE" }
if (-not (Test-Path $setup)) { throw "ISCC.exe reported success but $setup does not exist" }

Write-OpenMilaChecksum -Path $setup
Get-Item $setup | Select-Object Name, Length
