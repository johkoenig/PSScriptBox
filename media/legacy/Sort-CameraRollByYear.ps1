<#
.SYNOPSIS
    Sorts files in the Camera Roll folder into yearly subfolders based on the date in the filename.
.DESCRIPTION
    This script scans the Camera Roll folder for files with filenames in the format YY-MM-DD HH-MM-SS XXX.ext.
    It extracts the year, creates subfolders for each year (if they don't exist), and moves the files accordingly.
    Before moving, it displays the base folder and the number of files to be moved per year.
    The user must confirm before the operation starts.
.NOTES
    File Name      : Sort-CameraRollByYear.ps1
    Prerequisites  : PowerShell 5.1 or later, Windows 11
#>

# Header
$header = @"
+-------------------------------------------+
|  CAMERA ROLL PICTURE SORTER BY YEAR        |
+-------------------------------------------+
"@
Write-Host $header -ForegroundColor Cyan

# Define the base folder path
$userHome = $env:USERPROFILE
$baseFolder = Join-Path -Path $userHome -ChildPath "Nextcloud\Photos\Camera Roll"

# Check if the base folder exists
if (-not (Test-Path -Path $baseFolder -PathType Container))
{
    Write-Host "`n[ERROR] Base folder '$baseFolder' does not exist." -ForegroundColor Red
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
    exit
}

# Get all files in the base folder matching the pattern
$files = Get-ChildItem -Path $baseFolder -File |
        Where-Object { $_.Name -match '^\d{2}-\d{2}-\d{2} \d{2}-\d{2}-\d{2} .*' }

# Group files by year
$yearlyFiles = @{ }
foreach ($file in $files)
{
    $year = "20" + $file.Name.Substring(0, 2)
    if (-not $yearlyFiles.ContainsKey($year))
    {
        $yearlyFiles[$year] = @()
    }
    $yearlyFiles[$year] += $file
}

# Display the base folder and the number of files per year
Write-Host "`nBase folder: $baseFolder"
Write-Host "`nFiles to be moved:"
$totalFiles = 0
foreach ($year in ($yearlyFiles.Keys | Sort-Object))
{
    $count = $yearlyFiles[$year].Count
    $totalFiles += $count
    Write-Host "  $count files to $year" -ForegroundColor Yellow
}
Write-Host "`nTotal files to be moved: $totalFiles" -ForegroundColor Green

# Warning about Nextcloud client
Write-Host "`n[WARNING] The Nextcloud client may interfere with file operations during synchronization." -ForegroundColor Yellow
Write-Host "It is recommended to pause synchronization in the Nextcloud client before proceeding." -ForegroundColor Yellow
Write-Host "After the operation, resume synchronization in the Nextcloud client." -ForegroundColor Yellow

# Confirm before proceeding
Write-Host "`nPress ESC to cancel or any other key to continue..."
$key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
if ($key.VirtualKeyCode -eq 27)
{
# ESC key
    Write-Host "`nOperation cancelled." -ForegroundColor Red
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
    exit
}

# Move files to yearly subfolders
Write-Host "`nStarting to move files..."
$movedFiles = 0
$createdFolders = @()
foreach ($year in $yearlyFiles.Keys)
{
    $yearFolder = Join-Path -Path $baseFolder -ChildPath $year
    if (-not (Test-Path -Path $yearFolder -PathType Container))
    {
        New-Item -Path $yearFolder -ItemType Directory | Out-Null
        $createdFolders += $year
        Write-Host "  Created folder: $year" -ForegroundColor Green
    }
    foreach ($file in $yearlyFiles[$year])
    {
        $destination = Join-Path -Path $yearFolder -ChildPath $file.Name
        Move-Item -Path $file.FullName -Destination $destination -Force
        $movedFiles++
    }
}

# Summary
Write-Host "`n+-------------------------------------------+" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "+-------------------------------------------+" -ForegroundColor Cyan
Write-Host "`nBase folder: $baseFolder"
Write-Host "Total files moved: $movedFiles" -ForegroundColor Green
if ($createdFolders.Count -gt 0)
{
    Write-Host "Created folders: $( $createdFolders -join ', ' )" -ForegroundColor Green
}
Write-Host "`n[REMINDER] Resume synchronization in the Nextcloud client." -ForegroundColor Yellow

# Wait for user confirmation before closing
Write-Host "`nPress any key to exit..."
$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
