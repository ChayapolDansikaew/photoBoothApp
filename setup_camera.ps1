<#
.SYNOPSIS
Bind and attach a Nikon USB camera (VID 04b0) into WSL2 via usbipd-win,
then verify gphoto2 sees it. Must be run in an Administrator PowerShell.
#>
$ErrorActionPreference = "Stop"

if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
    Write-Error "usbipd-win is not installed. Run: winget install --exact dorssel.usbipd-win"
}

$lines = usbipd list
$nikon = $lines | Select-String -Pattern "04b0:|Nikon" | Select-Object -First 1
if (-not $nikon) {
    Write-Error "No Nikon USB device (VID 04b0) found. Turn on the Z6II and connect via USB."
}

$busId = ($nikon.Line -split "\s+")[0]
Write-Host "Found Nikon camera on BUSID $busId"
usbipd bind --busid $busId
usbipd attach --wsl --busid $busId

Write-Host "Verifying inside WSL..."
wsl gphoto2 --auto-detect
