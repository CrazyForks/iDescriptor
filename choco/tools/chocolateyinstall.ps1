$ErrorActionPreference = 'Stop'
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$url        = 'https://github.com/iDescriptor/iDescriptor/releases/download/v0.1.0/iDescriptor-v0.1.0-Windows_x86_64.msi'
$checksum   = 'bb803b3e4cfaa75068c28d15808284ad7d3400ed2bb7e98cdf1a2223d0543b6e'
$checksumType = 'sha256'

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'msi'
  url            = $url
  checksum       = $checksum
  checksumType   = $checksumType
  silentArgs     = "/quiet /norestart"
  validExitCodes = @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs