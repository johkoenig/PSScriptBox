<#
.SYNOPSIS
    Provides per-file video size optimization.

.DESCRIPTION
    Defines Invoke-MediaSizeOptimization, which encodes MOV and MP4 video with
    720p H.265 and keeps the source unchanged unless the MP4 is smaller and its
    file-level and capture date/time metadata has been verified.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7, FFmpeg, ExifTool.
    Uses Get-MediaDateMetadata, Invoke-MediaTool, Set-MediaFileTimestamps,
    and Get-LocalizedText.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Optimizes a MOV or MP4 file and writes a smaller MP4.

.DESCRIPTION
    Scales video to a maximum landscape size of 1280x720 or portrait size of
    720x1280, encodes H.265 with the libx265 encoder at the requested average
    video bitrate, and encodes audio at 96 kb/s. FFmpeg metadata is mapped and
    ExifTool copies all supported metadata. The operation fails safely if any
    file-level or capture date/time tag differs. Per-track creation and
    modification timestamps are not compared. Creation, last-write, and
    last-access timestamps are restored. By default, the source is moved to a
    sibling _orig backup with the source extension. With -ReplaceOriginal, the
    source is removed only after the MP4 is ready.

.PARAMETER Video
    MOV or MP4 file to optimize.

.PARAMETER FFmpegPath
    Path to the FFmpeg executable.

.PARAMETER ExifToolPath
    Path to the ExifTool executable.

.PARAMETER VideoBitrateKbps
    Target average video bitrate in kilobits per second. The default 1900
    targets approximately 90 MB for a six-minute video, depending on content.

.PARAMETER OriginalTimestamps
    Creation, last-write, and last-access timestamps captured before probing or
    reading the source. When omitted, the function captures them on entry.

.PARAMETER ReplaceOriginal
    Replaces the source video after the smaller MP4 has been created and verified.

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
function Invoke-MediaSizeOptimization
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Video,
        [Parameter(Mandatory)][string] $FFmpegPath,
        [Parameter(Mandatory)][string] $ExifToolPath,
        [Parameter(Mandatory)][bool] $ReplaceOriginal,
        [ValidateRange(500, 10000)][int] $VideoBitrateKbps = 1900,
        [hashtable] $OriginalTimestamps,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{ },
        [scriptblock] $Reporter = { }
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }
    $outputPath = Join-Path $Video.DirectoryName ($Video.BaseName + '.mp4')
    $backupPath = Join-Path $Video.DirectoryName ($Video.BaseName + '_orig' + $Video.Extension)
    $temporaryPath = Join-Path $Video.DirectoryName ('.optimize-{0}.mp4.part' -f [guid]::NewGuid().ToString('N'))
    $rollbackSourcePath = Join-Path $Video.DirectoryName ('.optimize-source-{0}.part' -f [guid]::NewGuid().ToString('N'))
    $samePathOutput = [string]::Equals(
            [System.IO.Path]::GetFullPath($Video.FullName),
            [System.IO.Path]::GetFullPath($outputPath),
            [System.StringComparison]::OrdinalIgnoreCase
    )
    $success = $false
    $skipped = $false
    $failureReason = $null
    $originalBytes = [long]0
    $resultBytes = [long]0
    $timestampPath = $Video.FullName
    $sourceTimestamps = $null

    try
    {
        $source = Get-Item -LiteralPath $Video.FullName -ErrorAction Stop
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

        if (-not $samePathOutput -and (Test-Path -LiteralPath $outputPath))
        {
            throw (Get-LocalizedText @localization -Text 'Output already exists: {0}' -Arguments @($outputPath))
        }
        if (-not $ReplaceOriginal -and (Test-Path -LiteralPath $backupPath))
        {
            throw (Get-LocalizedText @localization -Text 'Original backup already exists: {0}' -Arguments @($backupPath))
        }

        & $Reporter 'Host' $null (Get-LocalizedText @localization -Text 'Optimizing: {0}' -Arguments @($Video.Name))
        $sourceDateMetadata = Get-MediaDateMetadata -Path $Video.FullName -ExifToolPath $ExifToolPath `
            -UiLanguage $UiLanguage -Messages $Messages

        $scaleFilter = "scale=w='if(gte(iw,ih),min(1280,iw),-2)':h='if(gte(iw,ih),-2,min(1280,ih))'"
        $encodeResult = Invoke-MediaTool -ExecutablePath $FFmpegPath -Arguments @(
            '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
            '-i', $Video.FullName,
            '-map_metadata', '0', '-map_metadata:s', '0:s', '-map_chapters', '0',
            '-vf', $scaleFilter, '-c:v', 'libx265', '-tag:v', 'hvc1', '-pix_fmt', 'yuv420p',
            '-b:v', ('{0}k' -f $VideoBitrateKbps), '-preset', 'medium', '-b:a', '96k',
            '-f', 'mp4',
            $temporaryPath
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
            '-overwrite_original', '-P', '-TagsFromFile', $Video.FullName, '-all:all', $temporaryPath
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
            & $Reporter 'Host' 'DarkYellow' (Get-LocalizedText @localization -Text 'The MP4 was not smaller; the original was left unchanged.')
        }
        else
        {
            $sourceMovedPath = $null
            $outputCreated = $false
            try
            {
                if (-not $ReplaceOriginal)
                {
                    [System.IO.File]::Move($Video.FullName, $backupPath)
                    $sourceMovedPath = $backupPath
                    $timestampPath = $backupPath
                }
                elseif ($samePathOutput)
                {
                    [System.IO.File]::Move($Video.FullName, $rollbackSourcePath)
                    $sourceMovedPath = $rollbackSourcePath
                    $timestampPath = $rollbackSourcePath
                }

                [System.IO.File]::Move($temporaryPath, $outputPath)
                $outputCreated = $true
                Set-MediaFileTimestamps -Path $outputPath @sourceTimestamps

                if ($ReplaceOriginal -and $samePathOutput)
                {
                    Remove-Item -LiteralPath $rollbackSourcePath -Force -ErrorAction Stop
                    $timestampPath = $null
                }
                elseif ($ReplaceOriginal)
                {
                    Remove-Item -LiteralPath $Video.FullName -Force -ErrorAction Stop
                    $timestampPath = $null
                }
            }
            catch
            {
                $commitError = $_.Exception.Message
                $rollbackErrors = [System.Collections.Generic.List[string]]::new()
                if ($outputCreated -and (Test-Path -LiteralPath $outputPath))
                {
                    try
                    {
                        Remove-Item -LiteralPath $outputPath -Force -ErrorAction Stop
                    }
                    catch
                    {
                        $rollbackErrors.Add($_.Exception.Message)
                    }
                }
                if ($sourceMovedPath -and (Test-Path -LiteralPath $sourceMovedPath) -and
                        -not (Test-Path -LiteralPath $Video.FullName))
                {
                    try
                    {
                        [System.IO.File]::Move($sourceMovedPath, $Video.FullName)
                        $timestampPath = $Video.FullName
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
            & $Reporter 'Host' 'Green' (Get-LocalizedText -Text 'Optimized: {0:N1} MB -> {1:N1} MB' -Arguments @(
                ($originalBytes / 1MB), ($resultBytes / 1MB)
            ))
            & $Reporter 'Host' $null (Get-LocalizedText @localization -Text 'Created: {0}' -Arguments @($outputPath))
        }
    }
    catch
    {
        $failureReason = $_.Exception.Message
        & $Reporter 'Warning' $null (Get-LocalizedText @localization -Text "Could not optimize '{0}':`n{1}" -Arguments @($Video.Name, $failureReason))
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
        FilePath = $Video.FullName
        FailureReason = $failureReason
        OriginalBytes = $originalBytes
        ResultBytes = $resultBytes
    }
}
