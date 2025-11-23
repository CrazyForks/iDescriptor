$ErrorActionPreference = 'Stop'

$displayNamePattern = 'iDescriptor*'
Write-Host "Searching for installed application: '$displayNamePattern'"

$registryKey = Get-ItemProperty -Path @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
) -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $displayNamePattern } | Select-Object -First 1

if ($registryKey) {
  $productCode = $registryKey.PSChildName
  $foundName = $registryKey.DisplayName
  Write-Host "Found: '$foundName' with Product Code: '$productCode'"
  Write-Host "Calling msiexec directly to uninstall..."

  # Build the arguments for msiexec.exe
  $uninstallArgs = "/x `"$productCode`" /qn /norestart"
  Write-Host "Running: msiexec.exe $uninstallArgs"
  
  # Start the uninstaller process and wait for it to finish
  $process = Start-Process "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
  $exitCode = $process.ExitCode
  
  Write-Host "msiexec.exe finished with exit code: $exitCode"

  # Check if the exit code indicates success (0) or that a reboot is required (3010)
  $validExitCodes = @(0, 3010, 1641)
  if ($validExitCodes -notcontains $exitCode) {
    throw "Uninstallation failed with exit code $exitCode."
  } else {
    Write-Host "Uninstallation successful."
  }

} else {
  # If the key is not found, it might have been uninstalled already. Don't error.
  Write-Warning "Could not find a product starting with '$displayNamePattern' in the registry. The application may have already been uninstalled."
}