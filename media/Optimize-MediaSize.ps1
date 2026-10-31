<#
.SYNOPSIS
    Reduces sizes of inefficient videos and eligible JPEG photos.

.DESCRIPTION
    Processes MOV, MP4, JPG, and JPEG files from a path or recursively from a
    folder. Video behavior uses the existing 720p H.265 profile and codec
    skip rules. JPEG photos above 0.25 MB per megapixel are re-encoded at high
    quality without changing their pixel dimensions. Otherwise, photos larger
    than 6 MB are scaled proportionally toward an estimated 5 MB output size.
    Photos meeting neither threshold are skipped.

    Videos and photos are kept only when the result is smaller. FFmpeg and
    ExifTool copy and verify supported file-level and capture date/time
    metadata before replacement. Creation, last-write, and last-access file
    timestamps are preserved; NTFS change time cannot be set through the file
    APIs used here. By default, the source is moved to <Name>_orig with its
    original extension. -ReplaceOriginal removes the source only after the
    smaller result is created and verified. Existing backups are never
    overwritten.

.PARAMETER InputPath
    Optional path to a MOV, MP4, JPG, or JPEG file or folder containing these
    files. If omitted, the path is requested interactively.

.PARAMETER ReplaceOriginal
    Replaces the source with a smaller optimized file after successful encoding
    and date verification, without keeping an _orig backup. The source is not
    removed if encoding or date verification fails.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.EXAMPLE
    .\Optimize-MediaSize.ps1
    Prompts for a video file or folder and keeps originals as _orig backups.

.EXAMPLE
    .\Optimize-MediaSize.ps1 -InputPath 'C:\Videos' -WhatIf
    Previews which inefficiently encoded MOV and MP4 files would be processed.

.EXAMPLE
    .\Optimize-MediaSize.ps1 -InputPath 'C:\Videos\clip.mp4' -ReplaceOriginal
    Replaces the MP4 only with a smaller, date-verified MP4.

.EXAMPLE
    .\Optimize-MediaSize.ps1 -InputPath 'C:\Photos' -WhatIf
    Previews which large JPEG photos and inefficient videos would be processed.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7, FFmpeg with the
    libx265 and MJPEG encoders, FFprobe, and ExifTool. These tools must be
    available in PATH. Missing dependencies are reported individually with
    installation guidance. The script does not install software or require
    administrator rights.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>
# - Copilot

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'This user-facing script provides localized, color-coded console output.'
)]
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string] $InputPath,

    [switch] $ReplaceOriginal,

    [switch] $EnglishOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\common\internal\Get-LocalizedText.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-MissingDependencyReport.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\ConvertTo-QuotedArgument.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-MediaInputFile.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-MediaTool.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-MediaVideoInfo.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-MediaPhotoOptimizationPlan.ps1')
. (Join-Path $PSScriptRoot 'internal\Test-MediaVideoCodecEfficient.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-MediaDateTag.ps1')
. (Join-Path $PSScriptRoot 'internal\Set-MediaFileTimestamp.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-MediaSizeOptimization.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-MediaPhotoOptimization.ps1')

$OutputLanguage = if (
$EnglishOutput -or [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'de'
)
{
    'en'
}
else
{
    'de'
}
$MessagesPath = Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1'

$headerLines = @(
    '       .-------------------------------------------.'
    '      /                                           /|'
    '     /___________________________________________/ |'
    '     |  .-------------------------------------.  | |'
    '     |  | MEDIA SIZE OPTIMIZATION             |  | |'
    '         |  | VIDEO + JPEG PHOTOS: SIZE/DENSITY   |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)
Write-Host ''
foreach ($headerLine in $headerLines)
{
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText 'Optimizes inefficient videos and JPEG photos by size and density.' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
Write-Host (Get-LocalizedText 'Preserves supported file timestamps and verified capture dates.' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
Write-Host ''

$missingDependencyTemplate = Get-LocalizedText -Text 'Missing dependency: {0}' -Language $OutputLanguage -MessagesPath $MessagesPath
$ffmpegCommand = Get-Command -Name 'ffmpeg.exe', 'ffmpeg' -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
$ffprobeCommand = Get-Command -Name 'ffprobe.exe', 'ffprobe' -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
$exifToolCommand = Get-Command -Name 'exiftool.exe', 'exiftool' -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
$missingDependencies = [System.Collections.Generic.List[string]]::new()
if ($null -eq $ffmpegCommand)
{
    $missingDependencies.Add('FFmpeg')
}
if ($null -eq $ffprobeCommand)
{
    $missingDependencies.Add('FFprobe')
}
if ($null -eq $exifToolCommand)
{
    $missingDependencies.Add('ExifTool')
}
if ($missingDependencies.Count -gt 0)
{
    foreach ($dependency in $missingDependencies)
    {
        $guidance = if ($dependency -eq 'ExifTool')
        {
            Get-LocalizedText 'Install ExifTool with Chocolatey: choco install exiftool -y, or download from https://exiftool.org/.' -Language $OutputLanguage -MessagesPath $MessagesPath
        }
        else
        {
            Get-LocalizedText 'Install FFmpeg (including FFprobe) with Chocolatey: choco install ffmpeg -y.' -Language $OutputLanguage -MessagesPath $MessagesPath
        }
        $report = Get-MissingDependencyReport -Dependency $dependency -Guidance $guidance `
            -MessageTemplate $missingDependencyTemplate
        Write-Host $report.Message -ForegroundColor Yellow
        Write-Host "  $( $report.Guidance )"
    }
    exit 1
}

if ( [string]::IsNullOrWhiteSpace($InputPath))
{
    Write-Host (Get-LocalizedText 'Enter the path to a MOV, MP4, JPG, or JPEG file or a folder containing these files.' -Language $OutputLanguage -MessagesPath $MessagesPath)
    Write-Host (Get-LocalizedText 'Press Ctrl+C to cancel input.' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Yellow
    $InputPath = Read-Host -Prompt (Get-LocalizedText 'InputPath' -Language $OutputLanguage -MessagesPath $MessagesPath)
}

try
{
    $inputSelection = Get-MediaInputFile -Path $InputPath -UiLanguage $OutputLanguage -MessagesPath $MessagesPath
}
catch
{
    Write-Host (Get-LocalizedText -Text 'Error: {0}' -Arguments @($_.Exception.Message) -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Red
    exit 1
}

$mediaFiles = @($inputSelection.Files)
if ($mediaFiles.Count -eq 0)
{
    Write-Host (Get-LocalizedText 'No supported media files found.' -Language $OutputLanguage -MessagesPath $MessagesPath)
    exit 0
}
$videoFiles = @($mediaFiles | Where-Object { $_.Extension -in @('.mov', '.mp4') })
$photoFiles = @($mediaFiles | Where-Object { $_.Extension -in @('.jpg', '.jpeg') })

$basePath = $inputSelection.BasePath
$basePathPrefix = $basePath
if (-not $basePathPrefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar))
{
    $basePathPrefix += [System.IO.Path]::DirectorySeparatorChar
}
$summaryPathSegments = @($basePath.TrimEnd('\') -split '[\\/]' | Where-Object { $_ })
$summaryPath = '.\' + ((@($summaryPathSegments | Select-Object -Last 3)) -join '\') + '\'

Write-Host ''
Write-Host (Get-LocalizedText '=== Media size optimization: processing started ===' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($basePath) -Language $OutputLanguage -MessagesPath $MessagesPath)
Write-Host (Get-LocalizedText -Text 'Number of files: {0}' -Arguments @($mediaFiles.Count) -Language $OutputLanguage -MessagesPath $MessagesPath)
if ($videoFiles.Count -gt 0)
{
    Write-Host (Get-LocalizedText 'Video encoder: H.265 (HEVC/libx265), maximum 720p, target 1.9 Mb/s; preset medium' -Language $OutputLanguage -MessagesPath $MessagesPath)
    Write-Host (Get-LocalizedText 'Audio bitrate: 96 kb/s' -Language $OutputLanguage -MessagesPath $MessagesPath)
}
if ($photoFiles.Count -gt 0)
{
    Write-Host (Get-LocalizedText 'Photo profile: density-first 0.25 MB/MP threshold; otherwise photos over 6 MB are scaled toward an estimated 5 MB output; high JPEG quality' -Language $OutputLanguage -MessagesPath $MessagesPath)
}
if ($ReplaceOriginal)
{
    Write-Host (Get-LocalizedText 'Sources will be replaced after successful verification.' -Language $OutputLanguage -MessagesPath $MessagesPath)
}
else
{
    Write-Host (Get-LocalizedText 'Sources will be saved as _orig backups.' -Language $OutputLanguage -MessagesPath $MessagesPath)
}

$reporter = {
    param($Kind, $Color, $Text)
    if ($Kind -eq 'Warning')
    {
        Write-Warning $Text
        return
    }
    if ($Color)
    {
        Write-Host $Text -ForegroundColor $Color
    }
    else
    {
        Write-Host $Text
    }
}

$results = @()
$photoTargetSizeBytes = 6MB
$photoDensityThresholdMegabytesPerMegapixel = 0.25
$photoEstimatedOutputSizeBytes = [long](5 * 1MB)
$photoJpegQuality = 2
$photoExifToolConfigPath = Join-Path $PSScriptRoot 'internal\exiftool.config'
$photoOptimizationMarkerValue = 'Optimize-MediaSize/photo-v1'
$videoIndex = 0
$photoIndex = 0
for ($index = 0; $index -lt $mediaFiles.Count; $index++)
{
    $mediaFile = $mediaFiles[$index]
    $relativePath = $mediaFile.FullName.Substring($basePathPrefix.Length)

    if ($mediaFile.Extension -in @('.jpg', '.jpeg'))
    {
        $photoIndex++
        Write-Host ''
        Write-Host (Get-LocalizedText -Text '--- Photo {0}/{1}: {2} ---' -Arguments @($photoIndex, $photoFiles.Count, $relativePath) -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan

        $photo = $mediaFile
        $photoTimestamps = $null
        $photoPlan = $null
        try
        {
            $sourceFile = Get-Item -LiteralPath $photo.FullName -ErrorAction Stop
            $photo = $sourceFile
            $photoTimestamps = @{
                CreationTimeUtc = $sourceFile.CreationTimeUtc
                LastWriteTimeUtc = $sourceFile.LastWriteTimeUtc
                LastAccessTimeUtc = $sourceFile.LastAccessTimeUtc
            }
            $photoPlan = Get-MediaPhotoOptimizationPlan -Photo $photo `
                -FFprobePath $ffprobeCommand.Source -ExifToolPath $exifToolCommand.Source `
                -ExifToolConfigPath $photoExifToolConfigPath `
                -OptimizationMarkerValue $photoOptimizationMarkerValue `
                -SizeThresholdBytes $photoTargetSizeBytes `
                -DensityThresholdMegabytesPerMegapixel $photoDensityThresholdMegabytesPerMegapixel `
                -UiLanguage $OutputLanguage -MessagesPath $MessagesPath
        }
        catch
        {
            $failureReason = $_.Exception.Message
            Write-Warning (Get-LocalizedText -Text "Could not inspect '{0}':`n{1}" -Arguments @($relativePath, $failureReason) -Language $OutputLanguage -MessagesPath $MessagesPath)
            $results += [pscustomobject]@{
                Success = $false
                Skipped = $false
                FilePath = $photo.FullName
                FailureReason = $failureReason
                OriginalBytes = [long]0
                ResultBytes = [long]0
            }
            continue
        }

        if (-not $photoPlan.ShouldOptimize)
        {
            $skipReason = $photoPlan.SkipReason
            Write-Host $skipReason -ForegroundColor DarkYellow
            $results += [pscustomobject]@{
                Success = $false
                Skipped = $true
                FilePath = $photo.FullName
                FailureReason = $skipReason
                OriginalBytes = [long]0
                ResultBytes = [long]0
            }
            continue
        }

        $photoActionDescription = if ($photoPlan.OptimizationMode -eq 'Density')
        {
            Get-LocalizedText 'Recompress JPEG without resizing' -Language $OutputLanguage -MessagesPath $MessagesPath
        }
        else
        {
            Get-LocalizedText 'Resize and recompress JPEG' -Language $OutputLanguage -MessagesPath $MessagesPath
        }
        $photoAction = if ($ReplaceOriginal)
        {
            Get-LocalizedText -Text '{0} and replace source: {1}' -Arguments @($photoActionDescription, $photo.FullName) -Language $OutputLanguage -MessagesPath $MessagesPath
        }
        else
        {
            Get-LocalizedText -Text '{0} and back up source: {1}' -Arguments @($photoActionDescription, $photo.FullName) -Language $OutputLanguage -MessagesPath $MessagesPath
        }
        if (-not $PSCmdlet.ShouldProcess($photo.FullName, $photoAction))
        {
            $results += [pscustomobject]@{
                Success = $false
                Skipped = $true
                FilePath = $photo.FullName
                FailureReason = Get-LocalizedText 'Preview only; no files were changed.' -Language $OutputLanguage -MessagesPath $MessagesPath
                OriginalBytes = [long]0
                ResultBytes = [long]0
            }
            continue
        }

        try
        {
            $results += Invoke-MediaPhotoOptimization -Photo $photo -FFmpegPath $ffmpegCommand.Source `
                -FFprobePath $ffprobeCommand.Source -ExifToolPath $exifToolCommand.Source `
                -ExifToolConfigPath $photoExifToolConfigPath `
                -ReplaceOriginal $ReplaceOriginal.IsPresent -TargetSizeBytes $photoTargetSizeBytes `
                -OptimizationMarkerValue $photoOptimizationMarkerValue `
                -DensityThresholdMegabytesPerMegapixel $photoDensityThresholdMegabytesPerMegapixel `
                -EstimatedOutputSizeBytes $photoEstimatedOutputSizeBytes `
                -JpegQuality $photoJpegQuality -OptimizationPlan $photoPlan `
                -OriginalTimestamps $photoTimestamps `
                -UiLanguage $OutputLanguage -MessagesPath $MessagesPath -Reporter $reporter
        }
        catch
        {
            $failureReason = $_.Exception.Message
            Write-Warning (Get-LocalizedText -Text "Could not optimize '{0}':`n{1}" -Arguments @($relativePath, $failureReason) -Language $OutputLanguage -MessagesPath $MessagesPath)
            $results += [pscustomobject]@{
                Success = $false
                Skipped = $false
                FilePath = $photo.FullName
                FailureReason = $failureReason
                OriginalBytes = [long]0
                ResultBytes = [long]0
            }
        }
        continue
    }

    $videoIndex++
    $video = $mediaFile
    Write-Host ''
    Write-Host (Get-LocalizedText -Text '--- Video {0}/{1}: {2} ---' -Arguments @($videoIndex, $videoFiles.Count, $relativePath) -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan

    $videoTimestamps = $null
    try
    {
        $sourceFile = Get-Item -LiteralPath $video.FullName -ErrorAction Stop
        $videoTimestamps = @{
            CreationTimeUtc = $sourceFile.CreationTimeUtc
            LastWriteTimeUtc = $sourceFile.LastWriteTimeUtc
            LastAccessTimeUtc = $sourceFile.LastAccessTimeUtc
        }
        $videoInfo = Get-MediaVideoInfo -Path $video.FullName -FFprobePath $ffprobeCommand.Source `
            -UiLanguage $OutputLanguage -MessagesPath $MessagesPath
        Set-MediaFileTimestamp -Path $video.FullName @videoTimestamps `
            -UiLanguage $OutputLanguage -MessagesPath $MessagesPath -Confirm:$false -WhatIf:$false
    }
    catch
    {
        $inspectionError = $_.Exception.Message
        if ($null -ne $videoTimestamps)
        {
            try
            {
                Set-MediaFileTimestamp -Path $video.FullName @videoTimestamps `
                    -UiLanguage $OutputLanguage -MessagesPath $MessagesPath -Confirm:$false -WhatIf:$false
            }
            catch
            {
                $restorationError = Get-LocalizedText -Text 'Timestamp restoration failed: {0}' `
                    -Arguments @($_.Exception.Message) -Language $OutputLanguage -MessagesPath $MessagesPath
                $inspectionError = '{0}; {1}' -f $inspectionError, $restorationError
            }
        }
        Write-Warning (Get-LocalizedText -Text "Could not inspect '{0}':`n{1}" -Arguments @($relativePath, $inspectionError) -Language $OutputLanguage -MessagesPath $MessagesPath)
        $results += [pscustomobject]@{
            Success = $false
            Skipped = $false
            FilePath = $video.FullName
            FailureReason = $inspectionError
            OriginalBytes = [long]0
            ResultBytes = [long]0
        }
        continue
    }

    $codec = $videoInfo.Codec
    $videoBitrate = if ($null -eq $videoInfo.Bitrate)
    {
        [long]0
    }
    else
    {
        [long]$videoInfo.Bitrate
    }
    $backupPath = Join-Path $video.DirectoryName ($video.BaseName + '_orig' + $video.Extension)
    $hasOriginalBackup = Test-Path -LiteralPath $backupPath
    if (Test-MediaVideoCodecEfficient -Codec $codec -VideoBitrate $videoBitrate -HasOriginalBackup $hasOriginalBackup)
    {
        if ($codec -eq 'h264' -and $hasOriginalBackup)
        {
            $skipReason = Get-LocalizedText 'An _orig backup already exists; skipping to prevent repeat re-encoding.' -Language $OutputLanguage -MessagesPath $MessagesPath
        }
        elseif ($codec -eq 'h264' -and $videoBitrate -eq 0)
        {
            $skipReason = Get-LocalizedText 'H.264 bitrate is unavailable; skipping to avoid unnecessary re-encoding.' -Language $OutputLanguage -MessagesPath $MessagesPath
        }
        elseif ($codec -eq 'h264')
        {
            $skipReason = Get-LocalizedText -Text 'H.264 bitrate {0:N1} Mb/s is at or below the {1:N1} Mb/s threshold.' -Arguments @(
                ($videoBitrate / 1000000), 1.9
            ) -Language $OutputLanguage -MessagesPath $MessagesPath
        }
        else
        {
            $skipReason = Get-LocalizedText -Text 'Already uses an efficient video codec ({0}).' -Arguments @($codec) -Language $OutputLanguage -MessagesPath $MessagesPath
        }
        Write-Host $skipReason -ForegroundColor DarkYellow
        $results += [pscustomobject]@{
            Success = $false
            Skipped = $true
            FilePath = $video.FullName
            FailureReason = $skipReason
            OriginalBytes = [long]0
            ResultBytes = [long]0
        }
        continue
    }

    if ($codec -eq 'h264')
    {
        Write-Host (Get-LocalizedText -Text 'High-bitrate H.264 ({0:N1} Mb/s); converting to 720p H.265 at 1.9 Mb/s.' -Arguments @(
            ($videoBitrate / 1000000)
        ) -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor DarkYellow
    }

    $outputPath = Join-Path $video.DirectoryName ($video.BaseName + '.mp4')
    $action = if ($ReplaceOriginal)
    {
        Get-LocalizedText -Text 'Create optimized MP4 and replace source: {0}' -Arguments @($outputPath) -Language $OutputLanguage -MessagesPath $MessagesPath
    }
    else
    {
        Get-LocalizedText -Text 'Create optimized MP4 and back up source: {0}' -Arguments @($outputPath) -Language $OutputLanguage -MessagesPath $MessagesPath
    }

    if (-not $PSCmdlet.ShouldProcess($video.FullName, $action))
    {
        $results += [pscustomobject]@{
            Success = $false
            Skipped = $true
            FilePath = $video.FullName
            FailureReason = Get-LocalizedText 'Preview only; no files were changed.' -Language $OutputLanguage -MessagesPath $MessagesPath
            OriginalBytes = [long]0
            ResultBytes = [long]0
        }
        continue
    }

    try
    {
        $results += Invoke-MediaSizeOptimization -Video $video -FFmpegPath $ffmpegCommand.Source `
            -ExifToolPath $exifToolCommand.Source -ReplaceOriginal $ReplaceOriginal.IsPresent `
            -VideoBitrateKbps 1900 -OriginalTimestamps $videoTimestamps -UiLanguage $OutputLanguage `
            -MessagesPath $MessagesPath -Reporter $reporter
    }
    catch
    {
        Write-Warning (Get-LocalizedText -Text "Could not optimize '{0}':`n{1}" -Arguments @($relativePath, $_.Exception.Message) -Language $OutputLanguage -MessagesPath $MessagesPath)
        $results += [pscustomobject]@{
            Success = $false
            Skipped = $false
            FilePath = $video.FullName
            FailureReason = $_.Exception.Message
            OriginalBytes = [long]0
            ResultBytes = [long]0
        }
    }
}

$successfulResults = @($results | Where-Object { $_.Success })
$skippedResults = @($results | Where-Object { $_.Skipped })
$failedResults = @($results | Where-Object { -not $_.Success -and -not $_.Skipped })
$originalTotal = [long](($successfulResults | ForEach-Object { [long]$_.OriginalBytes } | Measure-Object -Sum).Sum)
$resultTotal = [long](($successfulResults | ForEach-Object { [long]$_.ResultBytes } | Measure-Object -Sum).Sum)
$savedMb = ($originalTotal - $resultTotal) / 1MB
$savedPercent = if ($originalTotal -gt 0)
{
    (1 - ($resultTotal / $originalTotal)) * 100
}
else
{
    0
}

Write-Host ''
Write-Host (Get-LocalizedText '=== Summary ===' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath) -Language $OutputLanguage -MessagesPath $MessagesPath)
Write-Host (Get-LocalizedText -Text 'Succeeded: {0}, skipped: {1}, failed: {2}' -Arguments @(
    $successfulResults.Count, $skippedResults.Count, $failedResults.Count
) -Language $OutputLanguage -MessagesPath $MessagesPath)
if ($successfulResults.Count -gt 0)
{
    Write-Host (Get-LocalizedText -Text 'Original total: {0:N2} MB' -Arguments @(($originalTotal / 1MB)) -Language $OutputLanguage -MessagesPath $MessagesPath)
    Write-Host (Get-LocalizedText -Text 'Result total: {0:N2} MB' -Arguments @(($resultTotal / 1MB)) -Language $OutputLanguage -MessagesPath $MessagesPath)
    Write-Host (Get-LocalizedText -Text 'Total saved: {0:N2} MB ({1:N1}%)' -Arguments @($savedMb, $savedPercent) -Language $OutputLanguage -MessagesPath $MessagesPath)
}
if ($ReplaceOriginal)
{
    Write-Host (Get-LocalizedText 'Original files were replaced after successful verification.' -Language $OutputLanguage -MessagesPath $MessagesPath)
}
else
{
    Write-Host (Get-LocalizedText 'Original files are saved as _orig backups; existing backups are preserved.' -Language $OutputLanguage -MessagesPath $MessagesPath)
}
Write-Host ''
Write-Host (Get-LocalizedText 'Failed files:' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
if ($failedResults.Count -eq 0)
{
    Write-Host (Get-LocalizedText '  None.' -Language $OutputLanguage -MessagesPath $MessagesPath)
}
else
{
    foreach ($result in $failedResults)
    {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($relativePath, $result.FailureReason) -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Yellow
    }
}
Write-Host ''
Write-Host (Get-LocalizedText 'Skipped files:' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
if ($skippedResults.Count -eq 0)
{
    Write-Host (Get-LocalizedText '  None.' -Language $OutputLanguage -MessagesPath $MessagesPath)
}
else
{
    foreach ($result in $skippedResults)
    {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($relativePath, $result.FailureReason) -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor DarkYellow
    }
}
