param(
    [Parameter(Mandatory = $true)]
    [string]$Date
)

$ErrorActionPreference = "Stop"

if (-not $Date) {
    Write-Error "MSYS2 archive date is required. Usage: get-msys2-archive.ps1 -Date <YYYY-MM-DD>"
    exit 1
}

Write-Host "Using MSYS2 archive release date: $Date"

# Base URL for the MSYS2 archive release
$baseUrl = "https://github.com/msys2/msys2-archive/releases/download/$Date"

$databases = @(
    "clang64",
    "clangarm64",
    "mingw32",
    "mingw64",
    "msys",
    "ucrt64"
)

$targetDir = "C:\msys64\var\lib\pacman\sync"

foreach ($db in $databases) {
    $dbUrl = "$baseUrl/$db.db"
    $sigUrl = "$baseUrl/$db.db.sig"

    $dbFile = Join-Path $targetDir "$db.db"
    $sigFile = Join-Path $targetDir "$db.db.sig"

    Write-Host "Downloading $db.db ..."
    Invoke-WebRequest -Uri $dbUrl -OutFile $dbFile

    Write-Host "Downloading $db.db.sig ..."
    Invoke-WebRequest -Uri $sigUrl -OutFile $sigFile
}