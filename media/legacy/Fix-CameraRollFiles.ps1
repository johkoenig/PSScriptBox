<#
.SYNOPSIS
    Fixes creation, modification, and EXIF dates for media files based on filename or metadata.
.DESCRIPTION
    This script extracts the timestamp from filenames (format: "YY-MM-DD HH-MM-SS") or falls back to metadata (EXIF).
    If the date is extracted from metadata, the file is renamed to "YY-MM-DD HH-MM-SS XXXX.ext".
    The script waits for user confirmation before exiting.
.NOTES
    Requires ExifTool by Phil Harvey (https://exiftool.org/).
    ExifTool must be in the system PATH or script directory.
#>

# Load Windows Forms assembly for folder dialog
Add-Type -AssemblyName System.Windows.Forms

# Display script purpose and ask for confirmation
Write-Host "`nThis script does the following:" -ForegroundColor Cyan
Write-Host "1. Extracts the timestamp from filenames (format: YY-MM-DD HH-MM-SS)." -ForegroundColor Cyan
Write-Host "2. If no timestamp is found in the filename, it uses metadata (EXIF) as a fallback." -ForegroundColor Cyan
Write-Host "3. If the date is extracted from metadata, the file is renamed to 'YY-MM-DD HH-MM-SS XXXX.ext'." -ForegroundColor Cyan
Write-Host "4. Updates the creation date, modification date, and EXIF metadata of all files." -ForegroundColor Cyan
Write-Host "`nDo you want to continue? (Y/N)" -ForegroundColor Yellow
$confirmation = Read-Host
if ($confirmation -ne "Y" -and $confirmation -ne "y")
{
    Write-Host "Script aborted by user." -ForegroundColor Red
    exit
}

# Function to select a folder
function Select-Folder
{
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select the folder containing the media files to process:"
    $folderBrowser.UseDescriptionForTitle = $true
    $folderBrowser.ShowNewFolderButton = $false

    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
    {
        return $folderBrowser.SelectedPath
    }
    else
    {
        return $null
    }
}

# Check if ExifTool is available
if (-not (Get-Command exiftool -ErrorAction SilentlyContinue))
{
    Write-Host "ExifTool is required but not found. Please install ExifTool from https://exiftool.org/" -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    exit
}

# Let the user select a folder
$selectedFolder = Select-Folder
if (-not $selectedFolder)
{
    Write-Host "No folder selected. Script will exit." -ForegroundColor Yellow
    Read-Host "Press Enter to exit..."
    exit
}

Write-Host "Selected folder: $selectedFolder" -ForegroundColor Green

# Get all media files in the selected folder and subfolders
$files = Get-ChildItem -File -Path $selectedFolder -Recurse | Where-Object {
    $_.Extension -match '\.(jpg|jpeg|png|mp4|mov|avi|mkv|gif|heic|webp|3gp|m4v)$'
}

if ($files.Count -eq 0)
{
    Write-Host "No supported media files found in the selected folder or its subfolders." -ForegroundColor Yellow
    Read-Host "Press Enter to exit..."
    exit
}

# Counter for renamed files
$fileCounter = 1
$errorCount = 0
$successCount = 0

# Process each file
foreach ($file in $files)
{
    $correctDateTime = $null
    $dateSource = "unknown"

    # --- Step 1: Try to extract date from filename (format: "YY-MM-DD HH-MM-SS") ---
    if ($file.Name -match '^(\d{2}-\d{2}-\d{2} \d{2}-\d{2}-\d{2})')
    {
        $timestampStr = $matches[1]
        $year = "20" + $timestampStr.Substring(0, 2)
        $month = $timestampStr.Substring(3, 2)
        $day = $timestampStr.Substring(6, 2)
        $hour = $timestampStr.Substring(9, 2)
        $minute = $timestampStr.Substring(12, 2)
        $second = $timestampStr.Substring(15, 2)

        try
        {
            $correctDateTime = [datetime]::new(
                    [int]$year,
                    [int]$month,
                    [int]$day,
                    [int]$hour,
                    [int]$minute,
                    [int]$second
            )
            $dateSource = "filename"
        }
        catch
        {
            Write-Host "Invalid date in filename for: $( $file.Name ). Skipping..." -ForegroundColor Red
            $errorCount++
            continue
        }
    }

    # --- Step 2: If no date in filename, try metadata (EXIF, CreateDate, etc.) ---
    if (-not $correctDateTime)
    {
        # Try DateTimeOriginal (EXIF)
        $exifDate = & exiftool -DateTimeOriginal -d "%Y-%m-%d %H:%M:%S" $file.FullName 2> $null | Select-String -Pattern "\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"
        if ($exifDate)
        {
            try
            {
                $correctDateTime = [datetime]::ParseExact($exifDate.Matches.Value, "yyyy-MM-dd HH:mm:ss", $null)
                $dateSource = "EXIF (DateTimeOriginal)"
            }
            catch
            {
                Write-Host "Invalid EXIF DateTimeOriginal for: $( $file.Name ). Skipping..." -ForegroundColor Red
                $errorCount++
                continue
            }
        }
        # Try CreateDate
        else
        {
            $createDate = & exiftool -CreateDate -d "%Y-%m-%d %H:%M:%S" $file.FullName 2> $null | Select-String -Pattern "\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"
            if ($createDate)
            {
                try
                {
                    $correctDateTime = [datetime]::ParseExact($createDate.Matches.Value, "yyyy-MM-dd HH:mm:ss", $null)
                    $dateSource = "EXIF (CreateDate)"
                }
                catch
                {
                    Write-Host "Invalid EXIF CreateDate for: $( $file.Name ). Skipping..." -ForegroundColor Red
                    $errorCount++
                    continue
                }
            }
        }
        # Try ModifyDate
        if (-not $correctDateTime)
        {
            $modifyDate = & exiftool -ModifyDate -d "%Y-%m-%d %H:%M:%S" $file.FullName 2> $null | Select-String -Pattern "\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"
            if ($modifyDate)
            {
                try
                {
                    $correctDateTime = [datetime]::ParseExact($modifyDate.Matches.Value, "yyyy-MM-dd HH:mm:ss", $null)
                    $dateSource = "EXIF (ModifyDate)"
                }
                catch
                {
                    Write-Host "Invalid EXIF ModifyDate for: $( $file.Name ). Skipping..." -ForegroundColor Red
                    $errorCount++
                    continue
                }
            }
        }
    }

    # --- If no date found, skip ---
    if (-not $correctDateTime)
    {
        Write-Host "No valid date found in filename or metadata for: $( $file.Name ). Skipping..." -ForegroundColor Yellow
        $errorCount++
        continue
    }

    $correctDate = $correctDateTime.ToString("yyyy-MM-dd HH:mm:ss")
    $correctDateFileName = $correctDateTime.ToString("yy-MM-dd HH-mm-ss")

    Write-Host "`nFile: $( $file.Name )" -ForegroundColor Green
    Write-Host "Date source: $dateSource"
    Write-Host "Extracted date: $correctDate"

    # --- Rename file (always, so that the order is corrected) ---
    $newFileName = "$correctDateFileName $($fileCounter.ToString("0000") )$( $file.Extension )"
    $newFilePath = Join-Path -Path $file.DirectoryName -ChildPath $newFileName

    # Check if file already exists
    while (Test-Path $newFilePath)
    {
        $fileCounter++
        $newFileName = "$correctDateFileName $($fileCounter.ToString("0000") )$( $file.Extension )"
        $newFilePath = Join-Path -path $file.DirectoryName -ChildPath $newFileName
    }

    try
    {
        Write-Host "Renaming file to: $newFileName" -ForegroundColor Cyan
        Rename-Item -Path $file.FullName -NewName $newFileName -Force -ErrorAction Stop
        $file = Get-Item $newFilePath  # Update file object
        $fileCounter++
    }
    catch
    {
        Write-Host "Failed to rename file: $( $file.Name ). Skipping..." -ForegroundColor Red
        $errorCount++
        continue
    }

    # --- Update file dates ---
    try
    {
        Write-Host "Updating file dates..." -ForegroundColor Cyan
        $file.CreationTime = $correctDateTime
        $file.LastWriteTime = $correctDateTime
    }
    catch
    {
        Write-Host "Failed to update file dates for: $( $file.Name ). Skipping..." -ForegroundColor Red
        $errorCount++
        continue
    }

    # --- Update EXIF/metadata ---
    try
    {
        Write-Host "Updating EXIF/metadata..." -ForegroundColor Cyan
        $exifToolOutput = & exiftool -overwrite_original `
            -DateTimeOriginal="$correctDate" `
            -CreateDate="$correctDate" `
            -ModifyDate="$correctDate" `
            -MediaCreateDate="$correctDate" `
            -MediaModifyDate="$correctDate" `
            -TrackCreateDate="$correctDate" `
            -TrackModifyDate="$correctDate" `
            $file.FullName 2>&1

        # Filter out minor warnings
        $exifToolOutput | Where-Object { $_ -notmatch "minor|not defined|Nothing to do" } | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    }
    catch
    {
        Write-Host "Failed to update EXIF/metadata for: $( $file.Name ). Skipping..." -ForegroundColor Red
        $errorCount++
        continue
    }

    # Reset LastWriteTime after ExifTool (as ExifTool updates it)
    try
    {
        $file.LastWriteTime = $correctDateTime
    }
    catch
    {
        Write-Host "Failed to reset LastWriteTime for: $( $file.Name )." -ForegroundColor Yellow
    }

    $successCount++
}

# Summary
Write-Host "`nProcessing complete." -ForegroundColor Green
Write-Host "Successfully processed files: $successCount" -ForegroundColor Green
Write-Host "Files with errors: $errorCount" -ForegroundColor Yellow

# Wait for user confirmation before exiting
Read-Host -Prompt "`nPress Enter to exit..."
