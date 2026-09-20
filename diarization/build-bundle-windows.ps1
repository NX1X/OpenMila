# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Builds the Python runtime OpenMila ships for speaker diarization on Windows:
# a relocatable CPython 3.11 with pyannote.audio and its dependencies, minus
# torch, which the app downloads on first use (DiarizationBootstrap).
#
# The Windows counterpart of diarization/build-bundle-linux.sh. Versions match
# upstream's macOS bundle exactly.
#
#   diarization\build-bundle-windows.ps1 [-OutputDir <path>]
param([string]$OutputDir)
$ErrorActionPreference = "Stop"

$PbsRelease = "20260510"
$PythonVersion = "3.11.15"
$PbsFile = "cpython-$PythonVersion+$PbsRelease-x86_64-pc-windows-msvc-install_only.tar.gz"
$PbsUrl = "https://github.com/astral-sh/python-build-standalone/releases/download/$PbsRelease/" +
          [uri]::EscapeDataString($PbsFile)
# From the release's own SHA256SUMS.
$PbsSha256 = "c0d6d9da1286640790c07f32c74516486c4ccd170a65952eebb3e125c34e6c67"

$PyannoteVersion = "3.3.2"
$TorchVersion = "2.2.2"        # pinned; downloaded at runtime by the app
$TorchaudioVersion = "2.2.2"

$root = Resolve-Path "$PSScriptRoot\.."
if (-not $OutputDir) { $OutputDir = Join-Path $root "diarization\out\PythonRuntime" }
$cache = Join-Path $root "diarization\cache"
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$tarball = Join-Path $cache $PbsFile

function Test-Checksum($path, $expected) {
    if (-not (Test-Path $path)) { return $false }
    (Get-FileHash $path -Algorithm SHA256).Hash.ToLower() -eq $expected.ToLower()
}

if (Test-Checksum $tarball $PbsSha256) {
    Write-Host "==> cached CPython tarball verified"
} else {
    Write-Host "==> downloading $PbsFile"
    curl.exe -fL --retry 3 -o "$tarball.part" $PbsUrl
    Move-Item -Force "$tarball.part" $tarball
    if (-not (Test-Checksum $tarball $PbsSha256)) { throw "CPython tarball checksum mismatch" }
}

$tmp = Join-Path $env:TEMP "openmila-diarization-$(New-Guid)"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    Write-Host "==> extracting CPython"
    tar -xzf $tarball -C $tmp
    $py = Join-Path $tmp "python\python.exe"
    if (-not (Test-Path $py)) { throw "python.exe missing after extraction" }
    & $py --version

    Write-Host "==> resolving pyannote.audio $PyannoteVersion and its dependencies"
    $venv = Join-Path $tmp "resolve-venv"
    & $py -m venv $venv
    $venvPy = Join-Path $venv "Scripts\python.exe"
    & $venvPy -m pip install --quiet --upgrade pip wheel
        # against the numpy 1.x C ABI.
    & $venvPy -m pip install --quiet "pyannote.audio==$PyannoteVersion" `
        "torch==$TorchVersion" "torchaudio==$TorchaudioVersion" `
        --index-url https://download.pytorch.org/whl/cpu `
        --extra-index-url https://pypi.org/simple
    $frozen = Join-Path $tmp "frozen.txt"
    # torch, torchaudio and the CUDA packages are downloaded by the app instead.
    # Exactly torch and torchaudio, not every name beginning with "torch":
    # torchmetrics is a pyannote dependency and must stay in the bundle.
    & $venvPy -m pip freeze | Where-Object { $_ -notmatch "^(torch|torchaudio|triton)==" -and $_ -notmatch "^nvidia-" } |
        Set-Content -Encoding ascii $frozen

    Write-Host "==> installing the frozen set into the bundle"
    $site = Join-Path $tmp "python\site-packages"
    New-Item -ItemType Directory -Force -Path $site | Out-Null
    # Built on the platform it targets, so pip picks the right wheels itself.
    & $venvPy -m pip install --quiet --no-deps --target $site --prefer-binary -r $frozen

    Write-Host "==> stripping caches and test trees"
    Get-ChildItem $site -Recurse -Directory -Filter "__pycache__" | Remove-Item -Recurse -Force
    Get-ChildItem $site -Recurse -Directory | Where-Object { $_.Name -in @("tests", "test") } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    $manifest = @"
OpenMila PythonRuntime bundle (Windows)
Generated: $((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))

python-build-standalone release: $PbsRelease
Python version: $PythonVersion
PBS tarball: $PbsFile
PBS sha256: $PbsSha256

pyannote.audio target version: $PyannoteVersion
torch/torchaudio (downloaded at runtime by the app): $TorchVersion/$TorchaudioVersion

Installed packages:
$((Get-Content $frozen) -join "`n")
"@
    Set-Content -Path (Join-Path $tmp "python\MANIFEST.txt") -Value $manifest

    Write-Host "==> writing $OutputDir"
    if (Test-Path $OutputDir) { Remove-Item -Recurse -Force $OutputDir }
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    Move-Item (Join-Path $tmp "python") (Join-Path $OutputDir "python")
    Write-Host "==> done"
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
