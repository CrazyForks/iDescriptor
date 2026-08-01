param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$MsiPath,
    [switch]$Push
)

$ErrorActionPreference = "Stop"
$packageDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$stagingDir = Join-Path $env:RUNNER_TEMP "iDescriptor-chocolatey"
$normalizedVersion = $Version.TrimStart('v')
if ($normalizedVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "Chocolatey version must be a three-part numeric version: $Version"
}

$resolvedMsi = (Resolve-Path $MsiPath).Path
$checksum = (Get-FileHash -LiteralPath $resolvedMsi -Algorithm SHA256).Hash.ToLowerInvariant()
$releaseTag = "v$normalizedVersion"
$msiName = "iDescriptor-$releaseTag-Windows_x86_64.msi"
$url = "https://github.com/iDescriptor/iDescriptor/releases/download/$releaseTag/$msiName"

if (Test-Path -LiteralPath $stagingDir) {
    Remove-Item -LiteralPath $stagingDir -Recurse -Force
}
Copy-Item -LiteralPath $packageDir -Destination $stagingDir -Recurse

$nuspecPath = Join-Path $stagingDir "idescriptor.nuspec"
$installPath = Join-Path $stagingDir "tools\chocolateyinstall.ps1"
$nuspec = (Get-Content -LiteralPath $nuspecPath -Raw).Replace('__VERSION__', $normalizedVersion)
$install = (Get-Content -LiteralPath $installPath -Raw).Replace('__URL__', $url).Replace('__CHECKSUM__', $checksum)
[IO.File]::WriteAllText($nuspecPath, $nuspec, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($installPath, $install, [Text.UTF8Encoding]::new($false))

Push-Location $stagingDir
try {
    choco pack $nuspecPath --output-directory $stagingDir
    if ($LASTEXITCODE -ne 0) { throw "choco pack failed with exit code $LASTEXITCODE" }
    if ($Push) {
        if (-not $env:CHOCOLATEY_API_KEY) { throw "CHOCOLATEY_API_KEY is required to push" }
        $package = Join-Path $stagingDir "idescriptor.$normalizedVersion.nupkg"
        choco push $package --source https://push.chocolatey.org/ --api-key $env:CHOCOLATEY_API_KEY
        if ($LASTEXITCODE -ne 0) { throw "choco push failed with exit code $LASTEXITCODE" }
    }
} finally {
    Pop-Location
}
