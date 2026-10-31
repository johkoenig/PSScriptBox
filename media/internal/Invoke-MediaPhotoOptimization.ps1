<#
.SYNOPSIS
    Resizes and recompresses a JPEG photo.

.DESCRIPTION
    Defines Invoke-MediaPhotoOptimization, which recompresses or resizes a JPEG,
    copies metadata, marks and verifies the staged output, and keeps the source
    unchanged unless the result is smaller and its dates are verified.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7, FFmpeg, FFprobe, ExifTool.
    Uses Get-MediaDateTag, Invoke-MediaTool, Set-MediaFileTimestamp,
    and Get-LocalizedText.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>
# - Copilot

<#
.SYNOPSIS
    Optimizes a JPEG photo and writes a smaller JPEG.

.DESCRIPTION
    Recompresses the photo without scaling or scales it to fit the requested
    dimensions, preserving EXIF orientation and supported metadata. It adds and
    verifies a PSScriptBox XMP profile marker on the staged output. The operation
    fails safely if marker or date verification fails. Creation, last-write, and
    last-access timestamps are restored. The source is changed only when the
    marked output is smaller.

.PARAMETER Photo
    JPEG file to optimize.

.PARAMETER FFmpegPath
    Path to the FFmpeg executable.

.PARAMETER FFprobePath
    Path to the FFprobe executable.

.PARAMETER ExifToolPath
    Path to the ExifTool executable.

.PARAMETER ExifToolConfigPath
    Path to the configuration defining the PSScriptBox XMP namespace.

.PARAMETER OptimizationMarkerValue
    Marker written to successfully optimized JPEG photos.

.PARAMETER ReplaceOriginal
    Replaces the source photo after the smaller JPEG has been created and verified.

.PARAMETER TargetSizeBytes
    Source size above which a photo can be resized when its density is within
    the density threshold.

.PARAMETER DensityThresholdMegabytesPerMegapixel
    Density above which a photo is recompressed without resizing.

.PARAMETER EstimatedOutputSizeBytes
    Estimated output file size used to derive the output pixel count.

.PARAMETER OptimizationPlan
    Previously evaluated photo dimensions and density-first optimization mode.

.PARAMETER JpegQuality
    FFmpeg MJPEG quality scale. Lower values produce higher quality; 2 is high quality.

.PARAMETER OriginalTimestamps
    Creation, last-write, and last-access timestamps captured before reading the
    source. When omitted, the function captures them on entry.

.PARAMETER UiLanguage
    Language of messages: 'de' selects the German catalog, anything else English.

.PARAMETER MessagesPath
    Path to the German message catalog.

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
        [Parameter(Mandatory)][string] $ExifToolConfigPath,
        [Parameter(Mandatory)][bool] $ReplaceOriginal,
        [string] $OptimizationMarkerValue = 'Optimize-MediaSize/photo-v1',
        [ValidateRange(1, [long]::MaxValue)][long] $TargetSizeBytes = 6MB,
        [ValidateRange(0.0, [double]::MaxValue)][double] $DensityThresholdMegabytesPerMegapixel = 0.25,
        [ValidateRange(1, [long]::MaxValue)][long] $EstimatedOutputSizeBytes = [long](5 * 1MB),
        [ValidateRange(2, 31)][int] $JpegQuality = 2,
        [pscustomobject] $OptimizationPlan,
        [hashtable] $OriginalTimestamps,
        [string] $UiLanguage = 'en',
        [string]$MessagesPath = '',
        [scriptblock] $Reporter = { }
    )
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
            throw (Get-LocalizedText -Text 'Only JPEG photos are supported: {0}' -Arguments @($photoPath) -Language $UiLanguage -MessagesPath $MessagesPath)
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

        if ($null -eq $OptimizationPlan)
        {
            $OptimizationPlan = Get-MediaPhotoOptimizationPlan -Photo $source `
                -FFprobePath $FFprobePath -ExifToolPath $ExifToolPath `
                -ExifToolConfigPath $ExifToolConfigPath -OptimizationMarkerValue $OptimizationMarkerValue `
                -SizeThresholdBytes $TargetSizeBytes `
                -DensityThresholdMegabytesPerMegapixel $DensityThresholdMegabytesPerMegapixel `
                -UiLanguage $UiLanguage -MessagesPath $MessagesPath
        }

        if (-not $OptimizationPlan.ShouldOptimize)
        {
            $skipped = $true
            $failureReason = $OptimizationPlan.SkipReason
            & $Reporter 'Host' 'DarkYellow' $failureReason
        }
        elseif (-not $ReplaceOriginal -and (Test-Path -LiteralPath $backupPath))
        {
            throw (Get-LocalizedText -Text 'Original backup already exists: {0}' -Arguments @($backupPath) -Language $UiLanguage -MessagesPath $MessagesPath)
        }
        else
        {
            & $Reporter 'Host' $null (Get-LocalizedText -Text 'Optimizing: {0}' -Arguments @($Photo.Name) -Language $UiLanguage -MessagesPath $MessagesPath)
            $sourceWidth = [long]$OptimizationPlan.Width
            $sourceHeight = [long]$OptimizationPlan.Height
            $encodeArguments = @(
                '-nostdin', '-hide_banner', '-loglevel', 'error', '-y', '-noautorotate',
                '-i', $photoPath, '-map_metadata', '0', '-frames:v', '1'
            )
            if ($OptimizationPlan.OptimizationMode -eq 'Size')
            {
                $scaleFactor = [Math]::Sqrt($EstimatedOutputSizeBytes / [double]$originalBytes)
                $targetWidth = [long][Math]::Max(2,[Math]::Floor($sourceWidth * $scaleFactor))
                $targetHeight = [long][Math]::Max(2,[Math]::Floor($sourceHeight * $scaleFactor))
                $targetWidth -= $targetWidth % 2
                $targetHeight -= $targetHeight % 2
                $scaleFilter = 'scale={0}:{1}:force_original_aspect_ratio=decrease:force_divisible_by=2' -f $targetWidth, $targetHeight
                $encodeArguments += @('-vf', $scaleFilter)
                & $Reporter 'Host' $null (Get-LocalizedText -Text 'Estimated JPEG dimensions: {0} x {1} -> {2} x {3} pixels (target {4:N1} MB).' -Arguments @(
                    $sourceWidth, $sourceHeight, $targetWidth, $targetHeight, ($EstimatedOutputSizeBytes / 1MB)
                ) -Language $UiLanguage -MessagesPath $MessagesPath)
            }
            else
            {
                & $Reporter 'Host' 'DarkYellow' (Get-LocalizedText -Text 'JPEG density {0:N3} MB/MP exceeds the {1:N2} MB/MP threshold; recompressing without resizing.' -Arguments @(
                    $OptimizationPlan.MegabytesPerMegapixel, $DensityThresholdMegabytesPerMegapixel
                ) -Language $UiLanguage -MessagesPath $MessagesPath)
            }
            $encodeArguments += @(
                '-c:v', 'mjpeg', '-q:v', [string]$JpegQuality,
                '-pix_fmt', 'yuvj420p', '-f', 'image2', $temporaryPath
            )

            $sourceDateMetadata = Get-MediaDateTag -Path $photoPath -ExifToolPath $ExifToolPath `
                -UiLanguage $UiLanguage -MessagesPath $MessagesPath

            $encodeResult = Invoke-MediaTool -ExecutablePath $FFmpegPath -Arguments $encodeArguments `
                -UiLanguage $UiLanguage -MessagesPath $MessagesPath
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
                throw (Get-LocalizedText -Text 'FFmpeg failed (exit code {0}): {1}' -Arguments @($encodeResult.ExitCode, $details) -Language $UiLanguage -MessagesPath $MessagesPath)
            }
            if (-not (Test-Path -LiteralPath $temporaryPath -PathType Leaf))
            {
                throw (Get-LocalizedText -Text 'FFmpeg did not create an output file.' -Language $UiLanguage -MessagesPath $MessagesPath)
            }
            if ((Get-Item -LiteralPath $temporaryPath -ErrorAction Stop).Length -le 0)
            {
                throw (Get-LocalizedText -Text 'FFmpeg created an empty output file.' -Language $UiLanguage -MessagesPath $MessagesPath)
            }

            $copyResult = Invoke-MediaTool -ExecutablePath $ExifToolPath -Arguments @(
                '-config', $ExifToolConfigPath, '-overwrite_original', '-P',
                '-TagsFromFile', $photoPath, '-all:all', $temporaryPath
            ) -UiLanguage $UiLanguage -MessagesPath $MessagesPath
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
                throw (Get-LocalizedText -Text 'ExifTool could not copy metadata (exit code {0}): {1}' -Arguments @($copyResult.ExitCode, $details) -Language $UiLanguage -MessagesPath $MessagesPath)
            }

            $outputDateMetadata = Get-MediaDateTag -Path $temporaryPath -ExifToolPath $ExifToolPath `
                -UiLanguage $UiLanguage -MessagesPath $MessagesPath
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
                throw (Get-LocalizedText -Text 'Date metadata changed during encoding; the original was not replaced. Tags: {0}' -Arguments @($tagList) -Language $UiLanguage -MessagesPath $MessagesPath)
            }

            $candidateBytes = [long](Get-Item -LiteralPath $temporaryPath -ErrorAction Stop).Length
            if ($candidateBytes -ge $originalBytes)
            {
                $skipped = $true
                $failureReason = Get-LocalizedText -Text 'No size reduction' -Language $UiLanguage -MessagesPath $MessagesPath
                & $Reporter 'Host' 'DarkYellow' (Get-LocalizedText -Text 'The optimized file was not smaller; the source was left unchanged.' -Language $UiLanguage -MessagesPath $MessagesPath)
            }
            else
            {
                $markerTag = '-XMP-psscriptbox:OptimizationProfile'
                $markerWriteResult = Invoke-MediaTool -ExecutablePath $ExifToolPath -Arguments @(
                    '-config', $ExifToolConfigPath, '-overwrite_original', '-P',
                    ('{0}={1}' -f $markerTag, $OptimizationMarkerValue), $temporaryPath
                ) -UiLanguage $UiLanguage -MessagesPath $MessagesPath
                if ($markerWriteResult.ExitCode -ne 0)
                {
                    $details = if ( [string]::IsNullOrWhiteSpace($markerWriteResult.StdErr))
                    {
                        $markerWriteResult.StdOut.Trim()
                    }
                    else
                    {
                        $markerWriteResult.StdErr.Trim()
                    }
                    throw (Get-LocalizedText -Text 'ExifTool failed to write the optimization marker for {0} (exit code {1}): {2}' -Arguments @(
                        $photoPath, $markerWriteResult.ExitCode, $details
                    ) -Language $UiLanguage -MessagesPath $MessagesPath)
                }

                $markerVerificationResult = Invoke-MediaTool -ExecutablePath $ExifToolPath -Arguments @(
                    '-config', $ExifToolConfigPath, '-s3', $markerTag, $temporaryPath
                ) -UiLanguage $UiLanguage -MessagesPath $MessagesPath
                if ($markerVerificationResult.ExitCode -ne 0)
                {
                    $details = if ( [string]::IsNullOrWhiteSpace($markerVerificationResult.StdErr))
                    {
                        $markerVerificationResult.StdOut.Trim()
                    }
                    else
                    {
                        $markerVerificationResult.StdErr.Trim()
                    }
                    throw (Get-LocalizedText -Text 'ExifTool failed to verify the optimization marker on {0} (exit code {1}): {2}' -Arguments @(
                        $photoPath, $markerVerificationResult.ExitCode, $details
                    ) -Language $UiLanguage -MessagesPath $MessagesPath)
                }
                if ($markerVerificationResult.StdOut.Trim() -cne $OptimizationMarkerValue)
                {
                    throw (Get-LocalizedText -Text 'ExifTool did not preserve the optimization marker on {0}.' -Arguments @(
                        $photoPath
                    ) -Language $UiLanguage -MessagesPath $MessagesPath)
                }

                Set-MediaFileTimestamp -Path $temporaryPath @sourceTimestamps `
                    -UiLanguage $UiLanguage -MessagesPath $MessagesPath -Confirm:$false -WhatIf:$false
                $candidateBytes = [long](Get-Item -LiteralPath $temporaryPath -ErrorAction Stop).Length
                if ($candidateBytes -ge $originalBytes)
                {
                    $skipped = $true
                    $failureReason = Get-LocalizedText -Text 'No size reduction' -Language $UiLanguage -MessagesPath $MessagesPath
                    & $Reporter 'Host' 'DarkYellow' (Get-LocalizedText -Text 'The optimized file was not smaller; the source was left unchanged.' -Language $UiLanguage -MessagesPath $MessagesPath)
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
                        Set-MediaFileTimestamp -Path $photoPath @sourceTimestamps `
                            -UiLanguage $UiLanguage -MessagesPath $MessagesPath -Confirm:$false -WhatIf:$false

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
                            throw (Get-LocalizedText -Text 'Commit failed: {0}; rollback also failed: {1}' -Arguments @(
                                $commitError, ($rollbackErrors -join '; ')
                            ) -Language $UiLanguage -MessagesPath $MessagesPath)
                        }
                        throw $commitError
                    }

                    $success = $true
                    $resultBytes = $candidateBytes
                    & $Reporter 'Host' 'Green' (Get-LocalizedText -Text 'Optimized: {0:N1} MB -> {1:N1} MB' -Arguments @(
                        ($originalBytes / 1MB), ($resultBytes / 1MB)
                    ) -Language $UiLanguage -MessagesPath $MessagesPath)
                    & $Reporter 'Host' $null (Get-LocalizedText -Text 'Created: {0}' -Arguments @($photoPath) -Language $UiLanguage -MessagesPath $MessagesPath)
                }
            }
        }
    }
    catch
    {
        $failureReason = $_.Exception.Message
        & $Reporter 'Warning' $null (Get-LocalizedText -Text "Could not optimize '{0}':`n{1}" -Arguments @($Photo.Name, $failureReason) -Language $UiLanguage -MessagesPath $MessagesPath)
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
                Set-MediaFileTimestamp -Path $timestampPath @sourceTimestamps `
                    -UiLanguage $UiLanguage -MessagesPath $MessagesPath -Confirm:$false -WhatIf:$false
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
            $cleanupMessage = Get-LocalizedText -Text 'Cleanup or timestamp restoration failed: {0}' -Arguments @($cleanupErrors -join '; ') -Language $UiLanguage -MessagesPath $MessagesPath
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
