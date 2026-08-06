$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$bonjourUrl = "https://github.com/tempx-x/bonjour-sdk/raw/refs/heads/main/bonjoursdksetup.exe"
$bonjourSha256 = "72AD5A8DA765427169C3126919A9AED6A8489F306C2461D62A13B92CAD8B8C00"
$tempDirectory = Join-Path $env:TEMP ("idescriptor-bonjour-" + [Guid]::NewGuid().ToString("N"))
$archivePath = Join-Path $tempDirectory "bonjoursdksetup.exe"
$msiPath = Join-Path $tempDirectory "Bonjour64.msi"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run as an administrator."
    }
}

try {
    Assert-Administrator
    New-Item -ItemType Directory -Path $tempDirectory | Out-Null

    Write-Host "Downloading the Bonjour installer..."
    Invoke-WebRequest -Uri $bonjourUrl -OutFile $archivePath -UseBasicParsing
    if (-not (Test-Path -LiteralPath $archivePath) -or (Get-Item -LiteralPath $archivePath).Length -eq 0) {
        throw "The Bonjour installer download was empty."
    }

    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    if ($actualHash -ne $bonjourSha256) {
        throw "Bonjour installer checksum mismatch. Expected $bonjourSha256, received $actualHash."
    }

    $tar = Join-Path $env:SystemRoot "System32\tar.exe"
    if (-not (Test-Path -LiteralPath $tar)) {
        throw "Windows tar.exe was not found: $tar"
    }

    & $tar -xf $archivePath -C $tempDirectory "Bonjour64.msi"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract Bonjour64.msi (tar exit code $LASTEXITCODE)."
    }
    if (-not (Test-Path -LiteralPath $msiPath)) {
        throw "Bonjour64.msi was not found in the downloaded installer."
    }

    $process = Start-Process -FilePath (Join-Path $env:SystemRoot "System32\msiexec.exe") `
        -ArgumentList @("/i", "`"$msiPath`"", "/qn", "/norestart") `
        -Wait -PassThru
    if ($process.ExitCode -notin @(0, 1641, 3010)) {
        throw "Bonjour installation failed with exit code $($process.ExitCode)."
    }

    Write-Host "Bonjour installation completed successfully."
    exit 0
}
catch {
    Write-Error "Bonjour installation failed: $($_.Exception.Message)"
    exit 1
}
finally {
    if (Test-Path -LiteralPath $tempDirectory) {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
