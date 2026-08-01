param(
    [Parameter(Mandatory = $true)][string]$DeployDir,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = "Stop"
$packageDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $packageDir "..\..\..")).Path
$deployRoot = (Resolve-Path $DeployDir).Path
$generatedPath = Join-Path $env:RUNNER_TEMP "iDescriptor-Files.wxs"

function Get-StableId([string]$Prefix, [string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value.ToLowerInvariant())
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return $Prefix + ([Convert]::ToHexString($hash).Substring(0, 24))
}

function ConvertTo-Guid([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value.ToLowerInvariant())
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    $guidBytes = New-Object byte[] 16
    [Array]::Copy($hash, $guidBytes, 16)
    return ([Guid]::new($guidBytes)).ToString().ToUpperInvariant()
}

function Escape-Xml([string]$Value) {
    return [Security.SecurityElement]::Escape($Value)
}

$files = Get-ChildItem -LiteralPath $deployRoot -File -Recurse | Sort-Object FullName
if (-not $files) {
    throw "Deployment directory is empty: $deployRoot"
}

$directories = @{}
foreach ($file in $files) {
    $relative = [IO.Path]::GetRelativePath($deployRoot, $file.FullName)
    $relativeDirectory = [IO.Path]::GetDirectoryName($relative)
    while ($relativeDirectory) {
        $directories[$relativeDirectory] = $true
        $parent = [IO.Path]::GetDirectoryName($relativeDirectory)
        if ($parent -eq $relativeDirectory) { break }
        $relativeDirectory = $parent
    }
}

$lines = [Collections.Generic.List[string]]::new()
$lines.Add('<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">')
$lines.Add('  <Fragment>')
$lines.Add('    <DirectoryRef Id="INSTALLFOLDER">')

function Add-DirectoryTree([string]$ParentPath, [int]$Indent) {
    $children = $directories.Keys | Where-Object {
        [IO.Path]::GetDirectoryName($_) -eq $ParentPath
    } | Sort-Object
    foreach ($child in $children) {
        $name = [IO.Path]::GetFileName($child)
        $id = Get-StableId "Dir" $child
        $spaces = ' ' * $Indent
        $lines.Add("$spaces<Directory Id=`"$id`" Name=`"$(Escape-Xml $name)`">")
        Add-DirectoryTree $child ($Indent + 2)
        $lines.Add("$spaces</Directory>")
    }
}

Add-DirectoryTree "" 6
$lines.Add('    </DirectoryRef>')
$lines.Add('  </Fragment>')
$lines.Add('  <Fragment>')
$lines.Add('    <ComponentGroup Id="ApplicationFiles">')

foreach ($file in $files) {
    $relative = [IO.Path]::GetRelativePath($deployRoot, $file.FullName)
    $relativeDirectory = [IO.Path]::GetDirectoryName($relative)
    $directoryId = if ($relativeDirectory) { Get-StableId "Dir" $relativeDirectory } else { "INSTALLFOLDER" }
    $componentId = Get-StableId "Cmp" $relative
    $fileId = if ($relative -ieq "idescriptor.exe") { "MainExecutable" } else { Get-StableId "File" $relative }
    $source = Escape-Xml $file.FullName
    $guid = ConvertTo-Guid $relative
    $lines.Add("      <Component Id=`"$componentId`" Directory=`"$directoryId`" Guid=`"$guid`">")
    $lines.Add("        <File Id=`"$fileId`" Source=`"$source`" KeyPath=`"yes`" Checksum=`"yes`" />")
    if ($fileId -eq "MainExecutable") {
        $lines.Add('        <Shortcut Id="StartMenuShortcut" Directory="ApplicationProgramsFolder" Name="iDescriptor" WorkingDirectory="INSTALLFOLDER" Advertise="yes" />')
        $lines.Add('        <Shortcut Id="DesktopShortcut" Directory="DesktopFolder" Name="iDescriptor" WorkingDirectory="INSTALLFOLDER" Advertise="yes" />')
    }
    $lines.Add('      </Component>')
}

$lines.Add('    </ComponentGroup>')
$lines.Add('  </Fragment>')
$lines.Add('</Wix>')
[IO.File]::WriteAllLines($generatedPath, $lines, [Text.UTF8Encoding]::new($false))

$normalizedVersion = $Version.TrimStart('v')
if ($normalizedVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "MSI version must be a three-part numeric version: $Version"
}

$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

& wix build `
    (Join-Path $packageDir "Product.wxs") `
    $generatedPath `
    -arch x64 `
    -ext WixToolset.UI.wixext `
    -ext WixToolset.Util.wixext `
    -d "Version=$normalizedVersion" `
    -d "MsiResources=$(Join-Path $packageDir 'resources')" `
    -d "SharedResources=$(Join-Path $repoRoot 'packaging\shared\resources\app-icon')" `
    -o $resolvedOutputPath
if ($LASTEXITCODE -ne 0) {
    throw "WiX failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $resolvedOutputPath)) {
    throw "WiX did not create the expected MSI: $resolvedOutputPath"
}
