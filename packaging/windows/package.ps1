# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Packages OpenMila for Windows as a portable zip: the app, the CLI, the MCP
# helper, the Swift runtime, whisper.cpp's DLLs, the resources and, when built,
# the diarization Python runtime.
#
#   packaging\windows\package.ps1 -Prefix C:\path\to\whisper-prefix [-Version 1.9.5+port.0]
param(
    [Parameter(Mandatory = $true)][string]$Prefix,
    [string]$Version,
    # Release is what a real package ships. CI passes debug so the zip step
    # reuses the build the earlier steps already made, instead of compiling
    # the whole UI toolkit a second time.
    [ValidateSet("debug", "release")][string]$Configuration = "release"
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

# link.exe takes /LIBPATH:, not -L.
$flags = @("-c", $Configuration, "-Xcc", "-I$Prefix\include", "-Xlinker", "/LIBPATH:$Prefix\lib")
Push-Location $root
swift build @flags --product openmila-cli
if ($LASTEXITCODE -ne 0) { throw "openmila-cli build failed" }
swift build @flags --product openmila-mcp
if ($LASTEXITCODE -ne 0) { throw "openmila-mcp build failed" }
$rootBin = (swift build @flags --show-bin-path | Select-Object -Last 1)
Pop-Location

# The icon as a resource inside openmila.exe. Swift on Windows has no asset
# catalogue: an .exe carries its icon as a Win32 RT_GROUP_ICON resource, so the
# icon has to go through a .rc compiled to a .res by rc.exe and handed to the
# linker. rc.exe ships with the Windows SDK that the MSVC toolchain Swift needs
# already installs, and vsdev.ps1 above puts it on PATH, so this adds no tool.
# If it is missing, packaging still succeeds and only the .exe's own icon is
# lost: the zip's openmila.ico, any shortcut made from it and the in-app About
# screen all still show the mark.
$appFlags = $flags
$rc = Get-Command rc.exe -ErrorAction SilentlyContinue
if ($rc) {
    $rcDir = Join-Path $out "winres"
    New-Item -ItemType Directory -Force -Path $rcDir | Out-Null
    Copy-Item (Join-Path $root "brand\icons\openmila.ico") $rcDir -Force
    # The .ico sits beside the .rc and is named without a path on purpose: a
    # backslash inside an .rc string literal is an escape character.
    Set-Content -Path (Join-Path $rcDir "openmila.rc") -Encoding ascii -Value @(
        "// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.",
        "// Written by packaging\windows\package.ps1 from brand/icons/openmila.ico.",
        "1 ICON `"openmila.ico`""
    )
    Push-Location $rcDir
    # try/catch as well as the exit code: PowerShell 7.4 turns a failing native
    # command into a terminating error under $ErrorActionPreference = "Stop",
    # and a missing icon must not fail the package.
    $rcBuilt = $false
    try {
        & $rc.Source /nologo /fo openmila.res openmila.rc
        $rcBuilt = $LASTEXITCODE -eq 0
    } catch {
        $rcBuilt = $false
    }
    Pop-Location
    if ($rcBuilt) { $appFlags += @("-Xlinker", (Join-Path $rcDir "openmila.res")) }
    else { Write-Warning "rc.exe failed: openmila.exe will ship without an icon resource" }
} else {
    Write-Warning "rc.exe not found: openmila.exe will ship without an icon resource"
}

$appBin = $null
Push-Location (Join-Path $root "Port\App")
# Matching scripts\port\build-windows.ps1: the default build system ignores
# the UI toolkit's platform conditions and drags the GTK backend in.
swift build --build-system native -j 3 @appFlags --product openmila
if ($LASTEXITCODE -eq 0) { $appBin = (swift build --build-system native @appFlags --show-bin-path | Select-Object -Last 1) }
Pop-Location

Copy-Item "$rootBin\openmila-cli.exe", "$rootBin\openmila-mcp.exe" $stage
if ($appBin) { Copy-Item "$appBin\openmila.exe" $stage }
# Every ggml backend DLL, including ggml-vulkan.dll when the build had the
# SDK: without it a machine with a graphics card quietly runs on the CPU.
Copy-Item "$Prefix\bin\*.dll" $stage -ErrorAction SilentlyContinue
Copy-Item "$Prefix\lib\*.dll" $stage -ErrorAction SilentlyContinue

# The Swift runtime DLLs, so the machine needs no Swift installation.
#
# These live at <SwiftRoot>\Runtimes\<version>\usr\bin, and swift.exe at
# <SwiftRoot>\Toolchains\<version>\usr\bin\swift.exe, which is five levels
# down. An earlier version of this walked up two levels and looked for
# Runtimes inside the toolchain, found nothing, copied nothing, and shipped a
# zip whose openmila.exe could not start: "Foundation.dll was not found".
$swiftExe = (Get-Command swift -ErrorAction Stop).Source
$swiftRoot = Split-Path (Split-Path (Split-Path (Split-Path (Split-Path $swiftExe -Parent) -Parent) -Parent) -Parent) -Parent
$runtimeRoot = Join-Path $swiftRoot "Runtimes"
$copied = 0
if (Test-Path $runtimeRoot) {
    Get-ChildItem $runtimeRoot -Recurse -Filter "*.dll" | ForEach-Object {
        Copy-Item $_.FullName $stage -Force
        $copied++
    }
}
Write-Host "Swift runtime: $copied DLLs from $runtimeRoot"

# The zip has to run on a machine with no Swift installed, and the only way to
# know it will is to check that its runtime is actually in there. A missing
# DLL is invisible until someone double-clicks the exe, which is exactly how
# the first build reached a tester.
$required = @("Foundation.dll", "swiftCore.dll", "swift_Concurrency.dll", "swift_StringProcessing.dll")
$missing = $required | Where-Object { -not (Test-Path (Join-Path $stage $_)) }
if ($missing) {
    throw "the package is missing Swift runtime DLLs and would not start: $($missing -join ', ')"
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

# The icon travels in the zip: openmila.ico for shortcuts and for any installer
# built from this payload, openmila.png beside the binaries because that is
# where Bundle.main - and so the About screen - looks for resources off macOS.
Copy-Item (Join-Path $root "brand\icons\openmila.ico") $stage -Force
Copy-Item (Join-Path $root "brand\icons\openmila-128.png") (Join-Path $stage "openmila.png") -Force

# Proof, not inventory: run the staged CLI with the Swift toolchain taken off
# PATH, so every DLL it needs has to come from the payload itself. The name
# check above catches the obvious hole; this catches the one nobody listed.
$savedPath = $env:PATH
$env:PATH = (($env:PATH -split ';') | Where-Object { $_ -and $_ -notmatch '(?i)swift' }) -join ';'
try {
    & (Join-Path $stage "openmila-cli.exe") | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "openmila-cli.exe exited $LASTEXITCODE" }
    Write-Host "Smoke: the payload starts with no Swift on PATH"
} catch {
    throw "the packaged binaries do not start from the payload alone: $_"
} finally {
    $env:PATH = $savedPath
}

$zip = Join-Path $out "OpenMila-$Version-win64.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path "$stage\*" -DestinationPath $zip
(Get-FileHash $zip -Algorithm SHA256).Hash.ToLower() + "  " + (Split-Path $zip -Leaf) |
    Set-Content -Encoding ascii "$zip.sha256"
Get-Item $zip | Select-Object Name, Length
