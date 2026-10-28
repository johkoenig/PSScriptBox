<#
.SYNOPSIS
    Copies one file to a Nextcloud-safe staging path.

.DESCRIPTION
    Defines Copy-FileToStaging, which streams a source file to a same-directory
    .part file, verifies its hash, and moves or atomically replaces the final
    destination only after the staging copy is complete.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
    Uses Get-FileSha256 and Get-LocalizedText.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Copies one file through a temporary .part file.

.DESCRIPTION
    Retries interrupted copies, reports byte-based progress, preserves source
    attributes and timestamps, verifies the source and staged hashes, and
    publishes the completed file with a same-directory move or atomic replace.

.PARAMETER SourceDirectory
    Directory containing the source file.

.PARAMETER DestinationDirectory
    Existing or newly created destination directory.

.PARAMETER FileName
    Name of the source and final destination file.

.PARAMETER RelativePath
    File path relative to the selected user folder, used in progress and errors.

.PARAMETER FileLength
    Expected source file length.

.PARAMETER ExpectedHash
    Expected SHA-256 hash captured during the copy plan.

.PARAMETER CompletedBytes
    Bytes already skipped or copied within the selected folder.

.PARAMETER TotalBytes
    Total source bytes in the selected folder.

.PARAMETER FolderName
    Display name of the selected user folder.

.PARAMETER Language
    'de' selects German messages; anything else selects English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.PARAMETER ProgressReporter
    Optional callback invoked with -Activity, -Status, and -PercentComplete
    during copy. Without a callback, no progress is reported.

.OUTPUTS
    None. Throws when copying, verification, or final publication fails.
#>
function Copy-FileToStaging
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $SourceDirectory,
        [Parameter(Mandatory)][string] $DestinationDirectory,
        [Parameter(Mandatory)][string] $FileName,
        [Parameter(Mandatory)][string] $RelativePath,
        [Parameter(Mandatory)][long] $FileLength,
        [Parameter(Mandatory)][string] $ExpectedHash,
        [Parameter(Mandatory)][long] $CompletedBytes,
        [Parameter(Mandatory)][long] $TotalBytes,
        [Parameter(Mandatory)][string] $FolderName,
        [string] $Language = 'en',
        [string]$MessagesPath = '',
        [AllowNull()][scriptblock] $ProgressReporter
    )
    [System.IO.Directory]::CreateDirectory($DestinationDirectory) | Out-Null
    $sourcePath = Join-Path $SourceDirectory $FileName
    $destinationPath = Join-Path $DestinationDirectory $FileName
    $temporaryFileName = '.PSScriptBox-copy-{0}.part' -f [guid]::NewGuid().ToString('N')
    $temporaryPath = Join-Path $DestinationDirectory $temporaryFileName
    $replacementBackupPath = Join-Path $DestinationDirectory (
    '.PSScriptBox-replaced-{0}.part' -f [guid]::NewGuid().ToString('N')
    )
    $source = Get-Item -LiteralPath $sourcePath -ErrorAction Stop
    if ($source.Length -ne $FileLength)
    {
        throw (Get-LocalizedText -Text 'Source file changed before copying: {0}' -Arguments @($RelativePath) -Language $Language -MessagesPath $MessagesPath)
    }

    $sourceTimestamps = @{
        CreationTimeUtc = $source.CreationTimeUtc
        LastWriteTimeUtc = $source.LastWriteTimeUtc
        LastAccessTimeUtc = $source.LastAccessTimeUtc
        Attributes = $source.Attributes
    }
    $activity = Get-LocalizedText -Text 'Copying folder {0}' -Arguments @($FolderName) -Language $Language -MessagesPath $MessagesPath
    $status = Get-LocalizedText -Text 'Copying file: {0}' -Arguments @($RelativePath) -Language $Language -MessagesPath $MessagesPath
    $copyError = $null

    try
    {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $sourceStream = $null
            $temporaryStream = $null
            try
            {
                $sourceStream = [System.IO.File]::Open(
                        $sourcePath,
                        [System.IO.FileMode]::Open,
                        [System.IO.FileAccess]::Read,
                        [System.IO.FileShare]::ReadWrite
                )
                $temporaryStream = [System.IO.FileStream]::new(
                        $temporaryPath,
                        [System.IO.FileMode]::CreateNew,
                        [System.IO.FileAccess]::Write,
                        [System.IO.FileShare]::None
                )
                $buffer = [byte[]]::new(1MB)
                $copiedBytes = [long]0
                $lastPercent = -1
                while (($bytesRead = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0)
                {
                    $temporaryStream.Write($buffer, 0, $bytesRead)
                    $copiedBytes += $bytesRead
                    $filePercent = if ($FileLength -gt 0)
                    {
                        [int](100 * $copiedBytes / $FileLength)
                    }
                    else
                    {
                        100
                    }
                    if ($filePercent -gt $lastPercent)
                    {
                        $overallPercent = if ($TotalBytes -gt 0)
                        {
                            (($CompletedBytes + ($FileLength * $filePercent / 100)) / $TotalBytes) * 100
                        }
                        else
                        {
                            $filePercent
                        }
                        if ($null -ne $ProgressReporter)
                        {
                            & $ProgressReporter -Activity $activity -Status $status `
                                -PercentComplete ([Math]::Min(100,[Math]::Max(0, [int]$overallPercent)))
                        }
                        $lastPercent = $filePercent
                    }
                }
                $temporaryStream.Flush($true)
                $copyError = $null
            }
            catch
            {
                $copyError = $_.Exception.Message
            }
            finally
            {
                if ($null -ne $temporaryStream)
                {
                    $temporaryStream.Dispose()
                }
                if ($null -ne $sourceStream)
                {
                    $sourceStream.Dispose()
                }
            }

            if (-not $copyError)
            {
                break
            }
            if (Test-Path -LiteralPath $temporaryPath)
            {
                Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction Stop
            }
            if ($attempt -lt 3)
            {
                Start-Sleep -Seconds 1
            }
        }

        if ($copyError)
        {
            throw (Get-LocalizedText -Text 'Could not copy {0} to a temporary file after {1} attempts: {2}' -Arguments @(
                $RelativePath, 3, $copyError
            ) -Language $Language -MessagesPath $MessagesPath)
        }

        $stagedFile = Get-Item -LiteralPath $temporaryPath -ErrorAction Stop
        if ($stagedFile.Length -ne $FileLength -or
                (Get-FileSha256 -Path $sourcePath) -ne $ExpectedHash -or
                (Get-FileSha256 -Path $temporaryPath) -ne $ExpectedHash)
        {
            throw (Get-LocalizedText -Text 'Source or staged file changed during copy: {0}' -Arguments @($RelativePath) -Language $Language -MessagesPath $MessagesPath)
        }

        try
        {
            if (Test-Path -LiteralPath $destinationPath -PathType Leaf)
            {
                [System.IO.File]::Replace($temporaryPath, $destinationPath, $replacementBackupPath)
                if (Test-Path -LiteralPath $replacementBackupPath)
                {
                    Remove-Item -LiteralPath $replacementBackupPath -Force -ErrorAction Stop
                }
            }
            else
            {
                [System.IO.File]::Move($temporaryPath, $destinationPath)
            }

            $publishedFile = Get-Item -LiteralPath $destinationPath -ErrorAction Stop
            $publishedFile.CreationTimeUtc = $sourceTimestamps.CreationTimeUtc
            $publishedFile.LastWriteTimeUtc = $sourceTimestamps.LastWriteTimeUtc
            $publishedFile.LastAccessTimeUtc = $sourceTimestamps.LastAccessTimeUtc
            $publishedFile.Attributes = $sourceTimestamps.Attributes
        }
        catch
        {
            throw (Get-LocalizedText -Text 'Could not publish the completed file {0}: {1}' -Arguments @(
                $RelativePath, $_.Exception.Message
            ) -Language $Language -MessagesPath $MessagesPath)
        }
    }
    finally
    {
        if (Test-Path -LiteralPath $temporaryPath)
        {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction Stop
        }
        if (Test-Path -LiteralPath $replacementBackupPath)
        {
            Remove-Item -LiteralPath $replacementBackupPath -Force -ErrorAction Stop
        }
    }
}
