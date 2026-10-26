<#
.SYNOPSIS
    Restores an original PDF backup over its processed PDF.

.DESCRIPTION
    Atomically replaces the processed PDF with the matching _orig PDF backup.
    The backup is removed when the replacement succeeds.

.PARAMETER OriginalFile
    The _orig PDF backup to restore.

.OUTPUTS
    System.Management.Automation.PSCustomObject. Reports the restore status and
    the processed PDF path.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Restores an original PDF backup over its processed PDF.

.DESCRIPTION
    Atomically replaces the processed PDF with the matching _orig PDF backup.
    The backup is removed when the replacement succeeds.

.PARAMETER OriginalFile
    The _orig PDF backup to restore.

.OUTPUTS
    System.Management.Automation.PSCustomObject. Reports the restore status and
    the processed PDF path.
#>
function Invoke-OriginalPdfRestore
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.IO.FileInfo] $OriginalFile)

    $processedBaseName = $OriginalFile.BaseName -replace '_orig$', ''
    $processedPath = Join-Path -Path $OriginalFile.DirectoryName -ChildPath ($processedBaseName + $OriginalFile.Extension)
    $processedBackupPath = Join-Path -Path $OriginalFile.DirectoryName -ChildPath (
    '.' + $processedBaseName + '.' + [guid]::NewGuid().ToString('N') + '.restore.bak'
    )
    $replacementCompleted = $false

    try
    {
        [System.IO.File]::Replace($OriginalFile.FullName, $processedPath, $processedBackupPath)
        $replacementCompleted = $true
        [System.IO.File]::Delete($processedBackupPath)
        return [pscustomobject]@{
            Success = $true
            ProcessedPath = $processedPath
            Error = $null
        }
    }
    catch
    {
        $errorMessage = $_.Exception.Message
        if (Test-Path -LiteralPath $processedBackupPath -PathType Leaf)
        {
            try
            {
                [System.IO.File]::Delete($processedBackupPath)
            }
            catch
            {
                $errorMessage += ' Cleanup also failed: ' + $_.Exception.Message
            }
        }

        if ($replacementCompleted -and -not (Test-Path -LiteralPath $processedBackupPath -PathType Leaf))
        {
            return [pscustomobject]@{
                Success = $true
                ProcessedPath = $processedPath
                Error = $null
            }
        }

        return [pscustomobject]@{
            Success = $false
            ProcessedPath = $processedPath
            Error = if ($replacementCompleted)
            {
                'The original was restored, but the processed PDF backup could not be removed: ' + $errorMessage
            }
            else
            {
                $errorMessage
            }
        }
    }
}
