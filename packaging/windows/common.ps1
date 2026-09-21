# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Shared by packaging\windows\package.ps1 (the portable zip) and
# packaging\windows\build-installer.ps1 (the Inno Setup installer). Its whole
# job is that both agree on the repository root, on how the version is
# resolved, and - the point of the file - on the ONE staging directory the
# payload is built in. The installer is compiled from the stage the zip was
# made from; nothing here builds or stages anything.

# The repository root, from the directory a script lives in.
function Get-OpenMilaRoot {
    param([Parameter(Mandatory = $true)][string]$ScriptRoot)
    (Resolve-Path (Join-Path $ScriptRoot "..\..")).Path
}

# The version to package. An explicit -Version wins; otherwise the app's own
# string, which is the single source of truth in the build.
function Resolve-OpenMilaVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$Version
    )
    if ($Version) { return $Version }
    $app = Join-Path $Root "Port\App\Sources\AppModel.swift"
    $match = Select-String -Path $app -Pattern 'static let version = "([^"]+)"'
    if (-not $match) { throw "no version in $app and none passed with -Version" }
    $match.Matches[0].Groups[1].Value
}

# The staging directory: the payload both artifacts are made from.
function Get-OpenMilaStage {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Version
    )
    Join-Path (Join-Path $Root "dist") "OpenMila-$Version-win64"
}

# A Windows VERSIONINFO resource takes four numbers, so "1.9.5-beta.2+port.0"
# cannot go in one. The first three numbers of the upstream version carry over
# and the port number becomes the fourth, which keeps the resource ordered the
# same way the release is: 1.9.5-beta.2+port.0 -> 1.9.5.0, +port.1 -> 1.9.5.1.
# The full string is still shown to the user through AppVersion and
# VersionInfoProductTextVersion, so nothing is lost, only made numeric.
function Get-OpenMilaFileVersion {
    param([Parameter(Mandatory = $true)][string]$Version)
    $core = ($Version -split '[-+]')[0]
    $parts = @($core -split '\.' | Where-Object { $_ -match '^\d+$' })
    while ($parts.Count -lt 3) { $parts += "0" }
    $port = 0
    if ($Version -match '\+port\.(\d+)') { $port = [int]$Matches[1] }
    ($parts[0..2] + @("$port")) -join '.'
}

# The checksum sidecar every OpenMila artifact ships: a lowercase hash, two
# spaces, the bare file name, which is what "sha256sum -c" expects.
function Write-OpenMilaChecksum {
    param([Parameter(Mandatory = $true)][string]$Path)
    (Get-FileHash $Path -Algorithm SHA256).Hash.ToLower() + "  " + (Split-Path $Path -Leaf) |
        Set-Content -Encoding ascii "$Path.sha256"
}
