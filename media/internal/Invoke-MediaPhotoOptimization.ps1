<#
.SYNOPSIS
    Resizes and recompresses a JPEG photo.

.DESCRIPTION
    Defines Invoke-MediaPhotoOptimization, which estimates output dimensions
    from the source pixel count and size, encodes at high quality, copies
    metadata, and keeps the source unchanged unless the result is smaller and
    its dates are verified.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7, FFmpeg, FFprobe, ExifTool.
    Uses Get-MediaDateMetadata, Invoke-MediaTool, Set-MediaFileTimestamps,
    and Get-LocalizedText.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Optimizes a JPEG photo and writes a smaller JPEG.

.DESCRIPTION
    Scales the photo to fit within the requested maximum dimensions without
    changing its EXIF orientation, encodes it with the MJPEG encoder at the
    requested quality, and copies supported metadata with ExifTool. The
    operation fails safely if file-level or capture date/time metadata differs.
    Creation, last-write, and last-access timestamps are restored. By default,
    the source is moved to a sibling _orig backup. With -ReplaceOriginal, the
    source is removed only after the new JPEG is ready.

.PARAMETER Photo
    JPEG file to optimize.

.PARAMETER FFmpegPath
    Path to the FFmpeg executable.

.PARAMETER FFprobePath
    Path to the FFprobe executable.

.PARAMETER ExifToolPath
    Path to the ExifTool executable.

.PARAMETER ReplaceOriginal
    Replaces the source photo after the smaller JPEG has been created and verified.

.PARAMETER TargetSizeBytes
    Minimum source size to optimize. Smaller photos are skipped.

.PARAMETER EstimatedOutputSizeBytes
    Estimated output file size used to derive the output pixel count.

.PARAMETER JpegQuality
    FFmpeg MJPEG quality scale. Lower values produce higher quality; 2 is high quality.

.PARAMETER OriginalTimestamps
    Creation, last-write, and last-access timestamps captured before reading the
    source. When omitted, the function captures them on entry.

.PARAMETER UiLanguage
    Language of messages: 'de' selects the German catalog, anything else English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.PARAMETER Reporter
    Receives regular and warning messages for display by the caller.

.OUTPUTS
    PSCustomObject with Success, Skipped, FilePath, FailureReason,
    OriginalBytes, and ResultBytes.
#>
function Invoke-MediaPhotoOptimization
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Photo,
        [Parameter(Mandatory)][string] $FFmpegPath,
        [Parameter(Mandatory)][string] $FFprobePath,
        [Parameter(Mandatory)][string] $ExifToolPath,
        [Parameter(Mandatory)][bool] $ReplaceOriginal,
        [ValidateRange(1, [long]::MaxValue)][long] $TargetSizeBytes = 6MB,
        [ValidateRange(1, [long]::MaxValue)][long] $EstimatedOutputSizeBytes = [long](5 * 1MB),
        [ValidateRange(2, 31)][int] $JpegQuality = 2,
        [hashtable] $OriginalTimestamps,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{ },
        [scriptblock] $Reporter = { param($Kind, $Color, $Text) }
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }
    $photoPath = $Photo.FullName
    $backupPath = Join-Path $Photo.DirectoryName ($Photo.BaseName + '_orig' + $Photo.Extension)
    $temporaryPath = Join-Path $Photo.DirectoryName ('.optimize-{0}.jpg.part' -f [guid]::NewGuid().ToString('N'))
    $rollbackPath = Join-Path $Photo.DirectoryName ('.optimize-source-{0}.part' -f [guid]::NewGuid().ToString('N'))
    $success = $false
    $skipped = $false
    $failureReason = $null
    $originalBytes = [long]0
    $resultBytes = [long]0
    $timestampPath = $photoPath
    $sourceTimestamps = $null

    try
    {
        if ($Photo.Extension -notin @('.jpg', '.jpeg'))
        {
            throw (Get-LocalizedText @localization -Text 'Only JPEG photos are supported: {0}' -Arguments @($photoPath))
        }

        $source = Get-Item -LiteralPath $photoPath -ErrorAction Stop
        $originalBytes = [long]$source.Length
        $sourceTimestamps = if ($null -ne $OriginalTimestamps)
        {
            $OriginalTimestamps
        }
        else
        {
            @{
                CreationTimeUtc = $source.CreationTimeUtc
                LastWriteTimeUtc = $source.LastWriteTimeUtc
                LastAccessTimeUtc = $source.LastAccessTimeUtc
            }
        }

        if ($originalBytes -le $TargetSizeBytes)
        {
            $skipped = $true
            $failureReason = Get-LocalizedText @localization -Text 'JPEG size {0:N1} MB is at or below the {1:N1} MB optimization threshold.' -Arguments @(
                ($originalBytes / 1MB), ($TargetSizeBytes / 1MB)
            )
            & $Reporter 'Host' 'DarkYellow' $failureReason
        }
        elseif (-not $ReplaceOriginal -and (Test-Path -LiteralPath $backupPath))
        {
            throw (Get-LocalizedText @localization -Text 'Original backup already exists: {0}' -Arguments @($backupPath))
        }
        else
        {
            & $Reporter 'Host' $null (Get-LocalizedText @localization -Text 'Optimizing: {0}' -Arguments @($Photo.Name))
            $dimensionResult = Invoke-MediaTool -ExecutablePath $FFprobePath -Arguments @(
                '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height',
                '-of', 'json', $photoPath
            ) -UiLanguage $UiLanguage -Messages $Messages
            if ($dimensionResult.ExitCode -ne 0)
            {
                $details = if ( [string]::IsNullOrWhiteSpace($dimensionResult.StdErr))
                {
                    $dimensionResult.StdOut.Trim()
                }
                else
                {
                    $dimensionResult.StdErr.Trim()
                }
                throw (Get-LocalizedText @localization -Text 'FFprobe failed to read JPEG dimensions for {0} (exit code {1}): {2}' -Arguments @(
                    $photoPath, $dimensionResult.ExitCode, $details
                ))
            }

            try
            {
                $dimensionData = ConvertFrom-Json -InputObject $dimensionResult.StdOut -ErrorAction Stop
                $dimensionStreams = @($dimensionData.streams)
                if ($dimensionStreams.Count -ne 1 -or
                        -not $dimensionStreams[0].PSObject.Properties['width'] -or
                        -not $dimensionStreams[0].PSObject.Properties['height'])
                {
                    throw 'FFprobe did not return one image stream with width and height.'
                }
                $sourceWidth = [long]$dimensionStreams[0].width
                $sourceHeight = [long]$dimensionStreams[0].height
                if ($sourceWidth -le 0 -or $sourceHeight -le 0)
                {
                    throw 'FFprobe returned non-positive image dimensions.'
                }
            }
            catch
            {
                throw (Get-LocalizedText @localization -Text 'FFprobe returned invalid JPEG dimensions for {0}: {1}' -Arguments @(
                    $photoPath, $_.Exception.Message
                ))
            }

            $scaleFactor = [Math]::Sqrt($EstimatedOutputSizeBytes / [double]$originalBytes)
            $targetWidth = [long][Math]::Max(2,[Math]::Floor($sourceWidth * $scaleFactor))
            $targetHeight = [long][Math]::Max(2,[Math]::Floor($sourceHeight * $scaleFactor))
            $targetWidth -= $targetWidth % 2
            $targetHeight -= $targetHeight % 2
            $scaleFilter = 'scale={0}:{1}:force_original_aspect_ratio=decrease:force_divisible_by=2' -f $targetWidth, $targetHeight
            & $Reporter 'Host' $null (Get-LocalizedText @localization -Text 'Estimated JPEG dimensions: {0} x {1} -> {2} x {3} pixels (target {4:N1} MB).' -Arguments @(
                $sourceWidth, $sourceHeight, $targetWidth, $targetHeight, ($EstimatedOutputSizeBytes / 1MB)
            ))
            $sourceDateMetadata = Get-MediaDateMetadata -Path $photoPath -ExifToolPath $ExifToolPath `
                -UiLanguage $UiLanguage -Messages $Messages

            $encodeResult = Invoke-MediaTool -ExecutablePath $FFmpegPath -Arguments @(
                '-nostdin', '-hide_banner', '-loglevel', 'error', '-y', '-noautorotate',
                '-i', $photoPath, '-map_metadata', '0', '-frames:v', '1',
                '-vf', $scaleFilter, '-c:v', 'mjpeg', '-q:v', [string]$JpegQuality,
                '-pix_fmt', 'yuvj420p', '-f', 'image2', $temporaryPath
            ) -UiLanguage $UiLanguage -Messages $Messages
            if ($encodeResult.ExitCode -ne 0)
            {
                $details = if ( [string]::IsNullOrWhiteSpace($encodeResult.StdErr))
                {
                    $encodeResult.StdOut.Trim()
                }
                else
                {
                    $encodeResult.StdErr.Trim()
                }
                throw (Get-LocalizedText @localization -Text 'FFmpeg failed (exit code {0}): {1}' -Arguments @($encodeResult.ExitCode, $details))
            }
            if (-not (Test-Path -LiteralPath $temporaryPath -PathType Leaf))
            {
                throw (Get-LocalizedText @localization -Text 'FFmpeg did not create an output file.')
            }
            if ((Get-Item -LiteralPath $temporaryPath -ErrorAction Stop).Length -le 0)
            {
                throw (Get-LocalizedText @localization -Text 'FFmpeg created an empty output file.')
            }

            $copyResult = Invoke-MediaTool -ExecutablePath $ExifToolPath -Arguments @(
                '-overwrite_original', '-P', '-TagsFromFile', $photoPath, '-all:all', $temporaryPath
            ) -UiLanguage $UiLanguage -Messages $Messages
            if ($copyResult.ExitCode -ne 0)
            {
                $details = if ( [string]::IsNullOrWhiteSpace($copyResult.StdErr))
                {
                    $copyResult.StdOut.Trim()
                }
                else
                {
                    $copyResult.StdErr.Trim()
                }
                throw (Get-LocalizedText @localization -Text 'ExifTool could not copy metadata (exit code {0}): {1}' -Arguments @($copyResult.ExitCode, $details))
            }

            Set-MediaFileTimestamps -Path $temporaryPath @sourceTimestamps
            $outputDateMetadata = Get-MediaDateMetadata -Path $temporaryPath -ExifToolPath $ExifToolPath `
                -UiLanguage $UiLanguage -Messages $Messages
            $changedTags = [System.Collections.Generic.List[string]]::new()
            foreach ($tagName in $sourceDateMetadata.Keys)
            {
                if (-not $outputDateMetadata.ContainsKey($tagName) -or
                        $sourceDateMetadata[$tagName] -cne $outputDateMetadata[$tagName])
                {
                    $changedTags.Add($tagName)
                }
            }
            foreach ($tagName in $outputDateMetadata.Keys)
            {
                if (-not $sourceDateMetadata.ContainsKey($tagName))
                {
                    $changedTags.Add($tagName)
                }
            }
            if ($changedTags.Count -gt 0)
            {
                $tagList = ($changedTags | Sort-Object -Unique) -join ', '
                throw (Get-LocalizedText @localization -Text 'Date metadata changed during encoding; the original was not replaced. Tags: {0}' -Arguments @($tagList))
            }

            $candidateBytes = [long](Get-Item -LiteralPath $temporaryPath -ErrorAction Stop).Length
            if ($candidateBytes -ge $originalBytes)
            {
                $skipped = $true
                $failureReason = Get-LocalizedText @localization -Text 'No size reduction'
                & $Reporter 'Host' 'DarkYellow' (Get-LocalizedText @localization -Text 'The optimized file was not smaller; the source was left unchanged.')
            }
            else
            {
                $sourceMovedPath = $null
                $outputCreated = $false
                try
                {
                    if (-not $ReplaceOriginal)
                    {
                        [System.IO.File]::Move($photoPath, $backupPath)
                        $sourceMovedPath = $backupPath
                        $timestampPath = $backupPath
                    }
                    else
                    {
                        [System.IO.File]::Move($photoPath, $rollbackPath)
                        $sourceMovedPath = $rollbackPath
                        $timestampPath = $rollbackPath
                    }

                    [System.IO.File]::Move($temporaryPath, $photoPath)
                    $outputCreated = $true
                    Set-MediaFileTimestamps -Path $photoPath @sourceTimestamps

                    if ($ReplaceOriginal)
                    {
                        Remove-Item -LiteralPath $rollbackPath -Force -ErrorAction Stop
                        $timestampPath = $null
                    }
                }
                catch
                {
                    $commitError = $_.Exception.Message
                    $rollbackErrors = [System.Collections.Generic.List[string]]::new()
                    if ($outputCreated -and (Test-Path -LiteralPath $photoPath))
                    {
                        try
                        {
                            Remove-Item -LiteralPath $photoPath -Force -ErrorAction Stop
                        }
                        catch
                        {
                            $rollbackErrors.Add($_.Exception.Message)
                        }
                    }
                    if ($sourceMovedPath -and (Test-Path -LiteralPath $sourceMovedPath) -and
                            -not (Test-Path -LiteralPath $photoPath))
                    {
                        try
                        {
                            [System.IO.File]::Move($sourceMovedPath, $photoPath)
                            $timestampPath = $photoPath
                        }
                        catch
                        {
                            $rollbackErrors.Add($_.Exception.Message)
                        }
                    }
                    if ($rollbackErrors.Count -gt 0)
                    {
                        throw (Get-LocalizedText @localization -Text 'Commit failed: {0}; rollback also failed: {1}' -Arguments @(
                            $commitError, ($rollbackErrors -join '; ')
                        ))
                    }
                    throw $commitError
                }

                $success = $true
                $resultBytes = $candidateBytes
                & $Reporter 'Host' 'Green' (Get-LocalizedText @localization -Text 'Optimized: {0:N1} MB -> {1:N1} MB' -Arguments @(
                    ($originalBytes / 1MB), ($resultBytes / 1MB)
                ))
                & $Reporter 'Host' $null (Get-LocalizedText @localization -Text 'Created: {0}' -Arguments @($photoPath))
            }
        }
    }
    catch
    {
        $failureReason = $_.Exception.Message
        & $Reporter 'Warning' $null (Get-LocalizedText @localization -Text "Could not optimize '{0}':`n{1}" -Arguments @($Photo.Name, $failureReason))
    }
    finally
    {
        $cleanupErrors = [System.Collections.Generic.List[string]]::new()
        if (Test-Path -LiteralPath $temporaryPath)
        {
            try
            {
                Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction Stop
            }
            catch
            {
                $cleanupErrors.Add($_.Exception.Message)
            }
        }

        if ($sourceTimestamps -and $timestampPath -and (Test-Path -LiteralPath $timestampPath -PathType Leaf))
        {
            try
            {
                Set-MediaFileTimestamps -Path $timestampPath @sourceTimestamps
            }
            catch
            {
                $cleanupErrors.Add($_.Exception.Message)
            }
        }

        if ($cleanupErrors.Count -gt 0)
        {
            $success = $false
            $skipped = $false
            $cleanupMessage = Get-LocalizedText @localization -Text 'Cleanup or timestamp restoration failed: {0}' -Arguments @($cleanupErrors -join '; ')
            if ($failureReason)
            {
                $failureReason = '{0}; {1}' -f $failureReason, $cleanupMessage
            }
            else
            {
                $failureReason = $cleanupMessage
            }
            & $Reporter 'Warning' $null $failureReason
        }
    }

    [pscustomobject]@{
        Success = $success
        Skipped = $skipped
        FilePath = $Photo.FullName
        FailureReason = $failureReason
        OriginalBytes = $originalBytes
        ResultBytes = $resultBytes
    }
}
