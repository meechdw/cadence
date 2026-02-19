#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"

$ARCH = (Get-CimInstance Win32_Processor).AddressWidth

if ($ARCH -eq 64) {
    $BINARY_NAME = "cadence-x86_64-windows.exe"
} else {
    Write-Error "error: unsupported architecture"
    exit 1
}

$InstallDir = "$Env:LOCALAPPDATA\Programs\cadence"
New-Item -ItemType Directory -Force -Path $InstallDir

$DOWNLOAD_URL = "https://github.com/meechdw/cadence/releases/latest/download/$BINARY_NAME"
Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile "$InstallDir\cadence.exe"

if ($Env:PATH -notlike "*$InstallDir*") {
    Write-Host "`nWarning: $InstallDir is not in your PATH"
    Write-Host "To complete installation, run the following command:"
    Write-Host "setx PATH `"$InstallDir;$Env:PATH`""
    Write-Host "`nThen restart your terminal"
} else {
    Write-Host "`nInstallation complete!"
}
