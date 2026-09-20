# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Builds (and optionally tests) OpenMila on Windows against a whisper.cpp
# prefix produced by build-whisper.ps1.
#
#   scripts\port\build-windows.ps1 -Prefix C:\path\to\whisper-prefix [-Test] [-App]
param(
    [Parameter(Mandatory = $true)][string]$Prefix,
    [switch]$Test,
    [switch]$App
)
$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
Set-Location $root

$flags = @("-Xcc", "-I$Prefix\include", "-Xlinker", "-L$Prefix\lib")
$env:Path = "$Prefix\bin;$env:Path"

Write-Host "==> core, CLI and MCP helper"
swift build @flags --product openmila-cli
if ($LASTEXITCODE -ne 0) { throw "openmila-cli build failed" }
swift build @flags --product openmila-mcp
if ($LASTEXITCODE -ne 0) { throw "openmila-mcp build failed" }

if ($Test) {
    Write-Host "==> port tests"
    swift test @flags --filter "^(ShimTests|RecordingTests)\."
    if ($LASTEXITCODE -ne 0) { throw "tests failed" }
}

if ($App) {
    Write-Host "==> desktop app"
    Set-Location (Join-Path $root "Port\App")
    swift build @flags --product openmila
    if ($LASTEXITCODE -ne 0) { throw "app build failed" }
}
