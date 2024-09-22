Push-Location "$(git rev-parse --show-toplevel)/shared"
. ./utilities.ps1
Pop-Location

Read-Env

# Get MongoDB connection details from environment variables
$mongoUri = [System.Environment]::GetEnvironmentVariable("MONGO_URI")
$targetDb = [System.Environment]::GetEnvironmentVariable("METADATA_DB")

if (-not $mongoUri -or -not $targetDb) {
    Write-Error "MONGO_URI and METADATA_DB environment variables must be set"
    exit 1
}
Write-Host $mongoUri

$dataFolderPath = Join-Path $PSScriptRoot "..\data"

Write-Output $dataFolderPath

Get-ChildItem -Path $dataFolderPath -Recurse -Filter *.json | ForEach-Object {
    $filePath = $_.FullName
    Write-Output "Importing $filePath into MongoDB..."
    $collectionName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
    $importCommand = "mongoimport --uri='$mongoUri' --db=$targetDb --collection=$collectionName --file=$filePath --jsonArray"
    Invoke-Expression $importCommand
}