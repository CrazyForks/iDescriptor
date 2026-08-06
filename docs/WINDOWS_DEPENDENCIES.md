# Windows dependencies

iDescriptor checks for three Windows components. The direct MSI and portable builds can install them from the diagnostics window. Microsoft Store builds open this guide because Store packages must not run bundled installer scripts or request elevation.

## Bonjour

Bonjour is required for AirPlay, automatic wireless device discovery, and network service discovery. iDescriptor can still open without it, but those features will not work.

Manual installation ways:

1. Install Bonjour through iTunes or another official Apple package
2. Use the following PowerShell script to install Bonjour:

Open a PowerShell terminal and run the following:

 ```powershell
$script = Join-Path $env:TEMP "install-bonjour.ps1"
Invoke-WebRequest "https://raw.githubusercontent.com/iDescriptor/iDescriptor/refs/heads/main/install-bonjour.ps1" -OutFile $script
Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
Remove-Item $script -Force
```

## Apple Mobile Device Support

Apple Mobile Device Support and its drivers are required for USB and network communication with iOS devices.

Manual installation ways:

1. Install the current 64-bit iTunes desktop package from Apple.
2. Use the following PowerShell script to install Apple Mobile Device Support

Open a PowerShell terminal and run the following:

```powershell
$script = Join-Path $env:TEMP "install-apple-drivers.ps1"
Invoke-WebRequest "https://raw.githubusercontent.com/iDescriptor/iDescriptor/refs/heads/main/install-apple-drivers.ps1" -OutFile $script
Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
Remove-Item $script -Force
```

## WinFsp

WinFsp is optional. It is required only when mounting an iOS device as a Windows drive.

Manual installation ways:

1. Install WinFsp 2.1 from its official GitHub release [WinFsp 2.1](https://github.com/winfsp/winfsp/releases/tag/v2.1)
2. Use the following PowerShell script to install WinFsp 2.1 

Open a PowerShell terminal and run the following:

```powershell
$script = Join-Path $env:TEMP "install-win-fsp.silent.bat"
Invoke-WebRequest "https://raw.githubusercontent.com/iDescriptor/iDescriptor/refs/heads/main/install-win-fsp.silent.bat" -OutFile $script
Start-Process cmd.exe -Verb RunAs -Wait -ArgumentList "/c `"$script`""
Remove-Item $script -Force
```
