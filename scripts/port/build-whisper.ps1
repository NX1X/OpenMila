# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Builds whisper.cpp at the commit .github/whisper-cpp-pin.txt names, as
# shared libraries, into -Prefix. Mirrors what ci/run.sh does on Linux.
param([Parameter(Mandatory = $true)][string]$Prefix)
$ErrorActionPreference = "Stop"

# Swift and CMake both need the MSVC toolchain on PATH.
. "$PSScriptRoot\vsdev.ps1"

$root = Resolve-Path "$PSScriptRoot\..\.."
$src = Join-Path $root "Packages\TranscriptionCore\vendor\whisper.cpp"
$pin = (Get-Content (Join-Path $root ".github\whisper-cpp-pin.txt")).Trim()
$actual = (git -C $src rev-parse HEAD).Trim()
if ($actual -ne $pin) { throw "whisper.cpp is at $actual, expected the pin $pin" }

# The Vulkan backend is built when the Vulkan SDK is installed (VULKAN_SDK is
# what its installer sets). Without it the CPU backend is built, which is what
# every machine falls back to anyway: the port probes for a real graphics
# device before it asks whisper.cpp for a GPU at all, so a Vulkan build costs
# nothing on a machine that has none.
$vulkan = "-DGGML_VULKAN=OFF"
if ($env:VULKAN_SDK -and (Test-Path $env:VULKAN_SDK)) {
    $vulkan = "-DGGML_VULKAN=ON"
    Write-Host "whisper.cpp: building with the Vulkan backend from $env:VULKAN_SDK"
} else {
    Write-Host "whisper.cpp: no Vulkan SDK (VULKAN_SDK is unset), building the CPU backend only"
}

# Ninja, not the Visual Studio generator. ggml's Vulkan backend configures a
# nested project to build its shader generator, and under the VS generator
# that nested build runs without the INCLUDE and LIB the developer shell
# exports, so cl.exe cannot compile even a trivial program:
#
#   The C compiler ... is not able to compile a simple test program
#
# Ninja passes the environment straight through, so the nested build sees the
# same toolchain as the outer one. It is also single-config, which is why the
# build and install steps below take no --config.
$generator = @()
if (Get-Command ninja -ErrorAction SilentlyContinue) {
    $generator = @("-G", "Ninja")
} else {
    Write-Warning "ninja is not on PATH; falling back to the default generator, which cannot build the Vulkan shaders"
}

cmake -S $src -B "$src\build-windows" @generator -DCMAKE_BUILD_TYPE=Release `
  -DBUILD_SHARED_LIBS=ON -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF `
  -DGGML_NATIVE=OFF $vulkan -DCMAKE_INSTALL_PREFIX="$Prefix"
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }
cmake --build "$src\build-windows" -j
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }
cmake --install "$src\build-windows"
if ($LASTEXITCODE -ne 0) { throw "cmake install failed" }
Get-ChildItem "$Prefix\lib", "$Prefix\bin" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
