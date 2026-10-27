## User Settings
$PhotoPaths = @(
    $( Join-Path -Path $env:USERPROFILE -ChildPath "Nextcloud\Photos\" ),
    $( Join-Path -Path $env:USERPROFILE -ChildPath "Nextcloud\_D21_KMJ_Eltern\111 Bilder" )
)

## Script Settings
$ffmpegPath = "C:\ProgramData\chocolatey\lib\ffmpeg\tools\ffmpeg\bin\ffmpeg.exe"

## Update video files
Write-Host -ForegroundColor Yellow "Clearing movie files..."
$errors = $false

# Create temp folder for video conversion
$tempFolderPrefix = "VideoConversion_"
$tempFolder = Join-Path -Path $env:Temp -ChildPath $( $tempFolderPrefix + $( Get-Random ) )
New-Item -Path $tempFolder -ItemType Directory -InformationAction SilentlyContinue | Out-Null

# Iterate over photo folders
foreach ($PhotoPath in $PhotoPaths)
{


    # Check path existence
    if ($( Test-Path -Path $PhotoPath -PathType Container ) -ne $true)
    {
        Write-Host -ForegroundColor Red "Skipping $PhotoPath --> Not Existing!"
        continue
    }

    # Clear out Apple Live Photos
    $movFileFilter = Join-Path -Path $PhotoPath -ChildPath "*.mov"
    $movFiles = $( Get-ChildItem -Path $movFileFilter -Recurse )

    # Iterate over each movie file
    foreach ($movFile in $movFiles)
    {

        Write-Host "-- Found video file" $movFile.Name "--> " -NoNewline
        $actionPerformed = $false

        # Delete Live Photos
        $folder = Split-Path -Path $movFile -Parent
        $filename = $( Get-ChildItem $movFile ).BaseName
        $ext = ".jpg"
        $imageFile = $( Join-Path -Path $folder -ChildPath $filename ) + $ext
        if (Test-Path -Path $imageFile -PathType Leaf)
        {
            Write-Host "Live Photo detected! --> " -NoNewline
            $actionPerformed = $true
            Remove-Item -Path $movFile -Force -ErrorAction SilentlyContinue
            if (Test-Path -Path $movFile -PathType Leaf)
            {
                $errors = $true
                Write-Host -ForegroundColor Red "Error while deleting the file!"
            }
            else
            {
                Write-Host -ForegroundColor Green "Deleted!"
            }
        }

        # Convert to a smaller size
        if (Test-Path -Path $ffmpegPath -PathType Leaf)
        {

            $actionPerformed = $true;
            Write-Host -ForegroundColor Yellow "Starting conversion"

            # Create paths
            $movParentFolder = $movFile.DirectoryName
            $movFileBaseName = $movFile.BaseName
            $movFileNewExt = ".mp4"
            $srcFilePath = $movFile.FullName
            $tmpFilePath = Join-Path -Path $tempFolder -ChildPath $( $movFileBaseName + $movFileNewExt )

            # Run conversion to temp folder
            . $ffmpegPath -i $srcFilePath -c:v h264 -crf 28 -tune film -b:a 96k -preset faster $tmpFilePath
            Write-Host -ForegroundColor Green "Conversion completed! --> " -NoNewline

            # Copy file to old location
            Move-Item -Path $tmpFilePath -Destination $movParentFolder -Force
            Write-Host -ForegroundColor Green "File moved to old location! --> " -NoNewline

            # Delete original file
            Remove-Item -Path $srcFilePath
            Write-Host -ForegroundColor Green "Old file deleted!"
        }

        # Report if no action has been performed
        if ($actionPerformed -eq $false)
        {
            Write-Host -ForegroundColor DarkGray "No action performed"
        }
    }
}
Write-Host -ForegroundColor Yellow "Clearing movie files... " -NoNewline
if ($errors)
{
    Write-Host -ForegroundColor Red "Completed with errors!"
}
else
{
    Write-Host -ForegroundColor Green "Completed!"
}

# Delete the temp folders
Remove-Item $( Join-Path -Path $env:Temp -ChildPath $( $tempFolderPrefix + "*" ) ) -Recurse

# exit
pause