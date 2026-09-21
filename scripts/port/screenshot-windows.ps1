# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Starts openmila.exe from a staged payload, waits for its window, captures
# it to PNG files, and closes it. CI uploads the images, which is the only way
# anyone without a Windows desktop gets to see what the WinUI build draws.
#
#   scripts\port\screenshot-windows.ps1 -Stage C:\path\to\stage -Out C:\path\to\shots
param(
    [Parameter(Mandatory = $true)][string]$Stage,
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$SettleSeconds = 20
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class OmWin {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
}
"@
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$exe = Join-Path $Stage "openmila.exe"
if (-not (Test-Path $exe)) { throw "no openmila.exe in $Stage" }

# A clean, separate data root so the run downloads nothing and shows the
# first-launch state; the model download banner is part of what to see.
$env:APPDATA = Join-Path $Out "appdata"
$env:LOCALAPPDATA = Join-Path $Out "localappdata"
New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA | Out-Null

function Capture-Window([string]$Name, [string]$Section) {
    if ($Section) { $env:OPENMILA_START_SECTION = $Section } else { Remove-Item Env:OPENMILA_START_SECTION -ErrorAction SilentlyContinue }
    $process = Start-Process -FilePath $exe -WorkingDirectory $Stage -PassThru
    try {
        $deadline = (Get-Date).AddSeconds($SettleSeconds + 40)
        do {
            Start-Sleep -Seconds 2
            $process.Refresh()
            $handle = $process.MainWindowHandle
        } while ($handle -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline -and -not $process.HasExited)
        if ($process.HasExited) { throw "openmila.exe exited with $($process.ExitCode) before showing a window" }
        if ($handle -eq [IntPtr]::Zero) { throw "openmila.exe showed no window within the deadline" }
        Start-Sleep -Seconds $SettleSeconds
        [OmWin]::ShowWindow($handle, 9) | Out-Null
        [OmWin]::SetForegroundWindow($handle) | Out-Null
        Start-Sleep -Seconds 2
        $rect = New-Object OmWin+RECT
        [OmWin]::GetWindowRect($handle, [ref]$rect) | Out-Null
        $width = $rect.R - $rect.L; $height = $rect.B - $rect.T
        if ($width -le 0 -or $height -le 0) { throw "window has no size: $width x $height" }
        Write-Host "$Name window: ${width}x${height} at $($rect.L),$($rect.T)"
        $bitmap = New-Object System.Drawing.Bitmap $width, $height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $dc = $graphics.GetHdc()
        [OmWin]::PrintWindow($handle, $dc, 2) | Out-Null   # PW_RENDERFULLCONTENT
        $graphics.ReleaseHdc($dc)
        $bitmap.Save((Join-Path $Out "$Name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose(); $bitmap.Dispose()
        return $handle
    } finally {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    }
}

# The recordings list beside its detail is the three-column layout, and the
# one worth a second image. OPENMILA_START_SECTION is honoured by the app so
# a capture can start there without driving the UI blind.
Capture-Window -Name "window-list" -Section "all" | Out-Null

$process = Start-Process -FilePath $exe -WorkingDirectory $Stage -PassThru
try {
    $deadline = (Get-Date).AddSeconds($SettleSeconds + 40)
    do {
        Start-Sleep -Seconds 2
        $process.Refresh()
        $handle = $process.MainWindowHandle
    } while ($handle -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline -and -not $process.HasExited)
    if ($process.HasExited) { throw "openmila.exe exited with $($process.ExitCode) before showing a window" }
    if ($handle -eq [IntPtr]::Zero) { throw "openmila.exe showed no window within the deadline" }
    Start-Sleep -Seconds $SettleSeconds
    [OmWin]::ShowWindow($handle, 9) | Out-Null
    [OmWin]::SetForegroundWindow($handle) | Out-Null
    Start-Sleep -Seconds 2

    $rect = New-Object OmWin+RECT
    [OmWin]::GetWindowRect($handle, [ref]$rect) | Out-Null
    $width = $rect.R - $rect.L; $height = $rect.B - $rect.T
    if ($width -le 0 -or $height -le 0) { throw "window has no size: $width x $height" }
    Write-Host "window: ${width}x${height} at $($rect.L),$($rect.T)"

    # Two captures: PrintWindow asks the window to draw itself, which works
    # even when it is not on top; the screen copy shows what a user sees,
    # caption bar included.
    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $dc = $graphics.GetHdc()
    [OmWin]::PrintWindow($handle, $dc, 2) | Out-Null   # PW_RENDERFULLCONTENT
    $graphics.ReleaseHdc($dc)
    $bitmap.Save((Join-Path $Out "window.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose(); $bitmap.Dispose()

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $shot = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
    $g = [System.Drawing.Graphics]::FromImage($shot)
    $g.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
    $shot.Save((Join-Path $Out "screen.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $shot.Dispose()
    Get-ChildItem $Out -Filter *.png | ForEach-Object { Write-Host "captured $($_.Name) ($($_.Length) bytes)" }
} finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    $log = Join-Path $env:LOCALAPPDATA "OpenMila\logs\openmila.log"
    if (Test-Path $log) { Copy-Item $log (Join-Path $Out "openmila.log") }
}
