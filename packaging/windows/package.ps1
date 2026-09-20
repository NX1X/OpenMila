# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Packages OpenMila for Windows as a portable zip: the app, the CLI, the MCP
# helper, the Swift runtime, whisper.cpp's DLLs, the resources and, when built,
# the diarization Python runtime.
#
#   packaging\windows\package.ps1 -Prefix C:\path\to\whisper-prefix [-Version 1.9.5+port.0]
param(
    [Parameter(Mandatory = $true)][string]$Prefix,
    [string]$Version
)
$ErrorActionPreference = "Stop"

# Swift and CMake both need the MSVC toolchain on PATH.
. "$PSScriptRoot\..\..\scripts\port\vsdev.ps1"
$root = Resolve-Path "$PSScriptRoot\..\.."
if (-not $Version) {
    $Version = (Select-String -Path "$root\Port\App\Sources\AppModel.swift" -Pattern 'static let version = "([^"]+)"').Matches[0].Groups[1].Value
}
$out = Join-Path $root "dist"
$stage = Join-Path $out "OpenMila-$Version-win64"
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$flags = @("-c", "release", "-Xcc", "-I$Prefix\include", "-Xlinker", "-L$Prefix\lib")
Push-Location $root
swift build @flags --product openmila-cli
swift build @flags --product openmila-mcp
$rootBin = (swift build @flags --show-bin-path | Select-Object -Last 1)
Pop-Location

$appBin = $null
Push-Location (Join-Path $root "Port\App")
swift build @flags --product openmila
if ($LASTEXITCODE -eq 0) { $appBin = (swift build @flags --show-bin-path | Select-Object -Last 1) }
Pop-Location

Copy-Item "$rootBin\openmila-cli.exe", "$rootBin\openmila-mcp.exe" $stage
if ($appBin) { Copy-Item "$appBin\openmila.exe" $stage }
Copy-Item "$Prefix\bin\*.dll" $stage -ErrorAction SilentlyContinue
Copy-Item "$Prefix\lib\*.dll" $stage -ErrorAction SilentlyContinue

# The Swift runtime DLLs, so the machine needs no Swift installation.
$runtime = Split-Path (Get-Command swift).Source -Parent
$runtimeRoot = Join-Path (Split-Path (Split-Path $runtime -Parent) -Parent) "Runtimes"
if (Test-Path $runtimeRoot) {
    Get-ChildItem $runtimeRoot -Recurse -Filter "*.dll" | ForEach-Object { Copy-Item $_.FullName $stage -Force }
}

# Resources beside the binaries: that is where Bundle.main looks.
foreach ($entry in @("ConnectionTestSample.wav", "ggml-silero-v5.1.2.bin", "DiarizationModels")) {
    Copy-Item (Join-Path $root "Mila\Resources\$entry") $stage -Recurse -Force
}
$python = Join-Path $root "diarization\out\PythonRuntime"
if (Test-Path $python) { Copy-Item $python $stage -Recurse -Force }
foreach ($doc in @("LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md", "README.md")) {
    Copy-Item (Join-Path $root $doc) $stage -Force
}

$zip = Join-Path $out "OpenMila-$Version-win64.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path "$stage\*" -DestinationPath $zip
(Get-FileHash $zip -Algorithm SHA256).Hash.ToLower() + "  " + (Split-Path $zip -Leaf) |
    Set-Content -Encoding ascii "$zip.sha256"
Get-Item $zip | Select-Object Name, Length
