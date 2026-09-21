# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Packages OpenMila for Windows: it builds the payload once into a staging
# directory - the app, the CLI, the MCP helper, the Swift runtime,
# whisper.cpp's DLLs, the resources and, when built, the diarization Python
# runtime - and zips it. That same stage is what the Inno Setup installer is
# compiled from, so the two artifacts can never disagree about their contents;
# build-installer.ps1 packages this stage and never rebuilds anything.
#
#   packaging\windows\package.ps1 -Prefix C:\path\to\whisper-prefix [-Version 1.9.5+port.0]
#   packaging\windows\package.ps1 -Prefix ... -Installer   # zip and installer
param(
    [Parameter(Mandatory = $true)][string]$Prefix,
    [string]$Version,
    # Release is what a real package ships. CI passes debug so the zip step
    # reuses the build the earlier steps already made, instead of compiling
    # the whole UI toolkit a second time.
    [ValidateSet("debug", "release")][string]$Configuration = "release",
    # Compile the installer from the same stage once the zip is written. Off by
    # default because it needs Inno Setup; the release workflow runs
    # build-installer.ps1 as its own step so a missing compiler fails there,
    # named, instead of silently shipping one artifact short.
    [switch]$Installer
)
$ErrorActionPreference = "Stop"

# Swift and CMake both need the MSVC toolchain on PATH.
. "$PSScriptRoot\..\..\scripts\port\vsdev.ps1"
. "$PSScriptRoot\common.ps1"
$root = Get-OpenMilaRoot -ScriptRoot $PSScriptRoot
$Version = Resolve-OpenMilaVersion -Root $root -Version $Version
$out = Join-Path $root "dist"
$stage = Get-OpenMilaStage -Root $root -Version $Version
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

# A window application, not a console one. Swift links an executable into the
# console subsystem by default, so launching openmila.exe flashed a console
# window before the app appeared - or, when the app could not start, a console
# window was the only thing the user saw. mainCRTStartup is the same entry the
# console subsystem uses; only the subsystem changes, so `--version` still
# runs, it just has no console to print to.
$appFlags += @("-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup")

$appBin = $null
Push-Location (Join-Path $root "Port\App")
# Matching scripts\port\build-windows.ps1: the default build system ignores
# the UI toolkit's platform conditions and drags the GTK backend in.
swift build --build-system native -j 3 @appFlags --product openmila
if ($LASTEXITCODE -eq 0) { $appBin = (swift build --build-system native @appFlags --show-bin-path | Select-Object -Last 1) }
Pop-Location

Copy-Item "$rootBin\openmila-cli.exe", "$rootBin\openmila-mcp.exe" $stage
if ($appBin) {
    Copy-Item "$appBin\openmila.exe" $stage
    # Everything the app build produced beside the exe, not the exe alone. The
    # WinUI backend loads Microsoft.WindowsAppRuntime.Bootstrap.dll, which
    # SwiftPM emits as a resource of the UI toolkit rather than linking in, and
    # a resource bundle is a directory the exe expects to find next to itself.
    # Copying only the exe is why the first installed build showed a console
    # window for a moment and disappeared.
    Copy-Item "$appBin\*.dll" $stage -Force -ErrorAction SilentlyContinue
    Get-ChildItem $appBin -Directory -Filter "*.resources" | ForEach-Object {
        Copy-Item $_.FullName $stage -Recurse -Force
    }
    # The bootstrap DLL has to sit beside the exe: the loader looks there, not
    # inside a resource bundle.
    Get-ChildItem $appBin -Recurse -Filter "Microsoft.WindowsAppRuntime.Bootstrap.dll" |
        Select-Object -First 1 | ForEach-Object { Copy-Item $_.FullName $stage -Force }
    if (-not (Test-Path (Join-Path $stage "Microsoft.WindowsAppRuntime.Bootstrap.dll"))) {
        throw "the app build produced no Microsoft.WindowsAppRuntime.Bootstrap.dll; openmila.exe would not start"
    }
}
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

# The Windows App Runtime, which the WinUI backend needs at run time.
#
# The bootstrap DLL beside the exe only FINDS this runtime; it does not
# contain it, so a machine without it starts openmila.exe and loses it again
# immediately. swift-winui pins Windows App SDK 1.5, so this is the matching
# redistributable, downloaded once and checked against its digest. The
# installer runs it; someone using the portable zip runs it themselves, which
# README-WINDOWS.txt in the zip explains.
$runtimeInstaller = Join-Path $stage "WindowsAppRuntimeInstall-x64.exe"
$runtimeURL = "https://aka.ms/windowsappsdk/1.5/1.5.240205001-preview1/windowsappruntimeinstall-x64.exe"
$runtimeSHA256 = "b906084876a0875d3401a7b4dc5a5a6da24ad7eb4a30ed8c05aa88085411817c"
if (-not (Test-Path $runtimeInstaller)) {
    curl.exe -fsSL --retry 4 -o $runtimeInstaller $runtimeURL
    if ($LASTEXITCODE -ne 0) { throw "could not download the Windows App Runtime from $runtimeURL" }
}
$actual = (Get-FileHash $runtimeInstaller -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $runtimeSHA256) {
    Remove-Item $runtimeInstaller -Force
    throw "the Windows App Runtime download has digest $actual, expected $runtimeSHA256"
}
Write-Host "Windows App Runtime: verified"

Set-Content -Path (Join-Path $stage "README-WINDOWS.txt") -Encoding ascii -Value @(
    "OpenMila, portable build",
    "",
    "Run openmila.exe. The first time on a machine, run",
    "WindowsAppRuntimeInstall-x64.exe first: the user interface is built on",
    "WinUI, which needs Microsoft's Windows App Runtime, and it installs for",
    "your user without asking for an administrator. The installer edition of",
    "OpenMila does this step for you.",
    "",
    "openmila-cli.exe needs none of that and works on its own.",
    "",
    "Nothing else has to be installed: the Swift runtime and the transcription",
    "engine travel in this folder."
)

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
    Write-Host "Smoke: the CLI starts with no Swift on PATH"

    # The app as well, which the CLI does not prove: openmila.exe loads the
    # WinUI backend and its Windows App Runtime, and the CLI loads neither.
    # `--version` returns before a window is created, but the loader has
    # already resolved every import by then, so a missing runtime fails here
    # rather than on a user's desktop. This is the check whose absence shipped
    # an installed build that showed a console window and vanished.
    $app = Join-Path $stage "openmila.exe"
    if (Test-Path $app) {
        if (-not $env:OPENMILA_SKIP_APP_SMOKE) {
            & $app --version | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "openmila.exe --version exited $LASTEXITCODE" }
            Write-Host "Smoke: the app starts with no Swift on PATH"
        } else {
            Write-Warning "OPENMILA_SKIP_APP_SMOKE is set: the app was not started"
        }
    } else {
        Write-Warning "no openmila.exe in the payload: the app build did not run"
    }
} catch {
    throw ("the packaged binaries do not start from the payload alone: $_`n" +
           "If this is openmila.exe on a machine that has never run it, install " +
           "the Windows App Runtime first: $stage\WindowsAppRuntimeInstall-x64.exe --quiet")
} finally {
    $env:PATH = $savedPath
}

$zip = Join-Path $out "OpenMila-$Version-win64.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path "$stage\*" -DestinationPath $zip
Write-OpenMilaChecksum -Path $zip
Get-Item $zip | Select-Object Name, Length

# The installer, from the stage above rather than from the zip: same payload,
# same version, one build.
# A failure inside the installer script is a terminating error there and
# propagates out of this one, so there is no exit code to re-check here.
if ($Installer) { & "$PSScriptRoot\build-installer.ps1" -Version $Version -Stage $stage }
