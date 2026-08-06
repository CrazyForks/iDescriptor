$packageArgs = @{
    packageName    = 'iDescriptor'
    fileType       = 'msi'
    url64bit       = '__URL__'
    checksum64     = '__CHECKSUM__'
    checksumType64 = 'sha256'
    silentArgs     = '/qn /norestart'
    validExitCodes = @(0, 3010)
}

Install-ChocolateyPackage @packageArgs
