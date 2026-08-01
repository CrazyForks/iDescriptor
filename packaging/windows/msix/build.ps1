param(
    [Parameter(Mandatory = $true)][string]$DeployDir,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$IdentityName,
    [Parameter(Mandatory = $true)][string]$Publisher
)

$ErrorActionPreference = "Stop"
$packageDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $packageDir "..\..\..")).Path
$stagingDir = Join-Path $env:RUNNER_TEMP "iDescriptor-msix"
$normalizedVersion = $Version.TrimStart('v')
if ($normalizedVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "MSIX version must be a three-part numeric version: $Version"
}
$msixVersion = "$normalizedVersion.0"

if (Test-Path -LiteralPath $stagingDir) {
    Remove-Item -LiteralPath $stagingDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null
Copy-Item -Path (Join-Path (Resolve-Path $DeployDir).Path '*') -Destination $stagingDir -Recurse -Force

$manifest = Get-Content -LiteralPath (Join-Path $packageDir "AppxManifest.xml.in") -Raw
$manifest = $manifest.Replace('@IDENTITY_NAME@', $IdentityName)
$manifest = $manifest.Replace('@PUBLISHER@', $Publisher)
$manifest = $manifest.Replace('@VERSION@', $msixVersion)
[IO.File]::WriteAllText((Join-Path $stagingDir "AppxManifest.xml"), $manifest, [Text.UTF8Encoding]::new($false))

$assetDir = Join-Path $stagingDir "Assets"
New-Item -ItemType Directory -Force -Path $assetDir | Out-Null
$icon = Join-Path $repoRoot "packaging\shared\resources\app-icon\icon-512.png"
$assets = @{
    "StoreLogo.png" = "50x50"
    "Square44x44Logo.png" = "44x44"
    "Square150x150Logo.png" = "150x150"
    "Square310x310Logo.png" = "310x310"
    "Wide310x150Logo.png" = "310x150"
}
foreach ($asset in $assets.GetEnumerator()) {
    & magick $icon -background none -gravity center -resize $asset.Value -extent $asset.Value (Join-Path $assetDir $asset.Key)
    if ($LASTEXITCODE -ne 0) { throw "Failed to generate MSIX asset $($asset.Key)" }
}

$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
& makeappx pack /d $stagingDir /p $resolvedOutputPath /o
if ($LASTEXITCODE -ne 0) { throw "makeappx failed with exit code $LASTEXITCODE" }
& makeappx validate /p $resolvedOutputPath
if ($LASTEXITCODE -ne 0) { throw "makeappx validation failed with exit code $LASTEXITCODE" }
