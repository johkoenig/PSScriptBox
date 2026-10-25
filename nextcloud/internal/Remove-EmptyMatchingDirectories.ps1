<#
.SYNOPSIS
    Provides the empty-folder cleanup helper for the Nextcloud scripts.

.DESCRIPTION
    Defines Remove-EmptyMatchingDirectories. Has no dependencies on other helpers.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Removes empty local subfolders with an existing Nextcloud counterpart.

.DESCRIPTION
    Checks subfolders in descending path length so nested empty folders are
    removed first. Links and junctions are never followed or deleted, and
    non-empty folders are never deleted recursively. A folder is deleted only
    when it is empty and the same relative folder exists in the Nextcloud
    destination. Failures are collected and returned rather than written to the
    console, so the caller decides how to report them.

.PARAMETER SourcePath
    Local main folder.

.PARAMETER DestinationPath
    Corresponding Nextcloud main folder.

.PARAMETER RelativeDirectories
    Relative paths of subfolders found in both inventories.

.OUTPUTS
    PSCustomObject with DeletedCount (number of deleted folders) and
    FailedDirectories (objects with RelativePath and Message for each failure).
#>
function Remove-EmptyMatchingDirectories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $SourcePath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $DestinationPath,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $RelativeDirectories
    )

    $deletedCount = 0
    $failedDirectories = [System.Collections.Generic.List[object]]::new()
    foreach ($relativeDirectory in ($RelativeDirectories | Sort-Object { $_.Length } -Descending)) {
        $sourceDirectoryPath = Join-Path $SourcePath $relativeDirectory
        $destinationDirectoryPath = Join-Path $DestinationPath $relativeDirectory
        try {
            if (-not (Test-Path -LiteralPath $sourceDirectoryPath -PathType Container) -or
                -not (Test-Path -LiteralPath $destinationDirectoryPath -PathType Container)) {
                continue
            }
            $sourceDirectory = Get-Item -LiteralPath $sourceDirectoryPath -Force -ErrorAction Stop
            $destinationDirectory = Get-Item -LiteralPath $destinationDirectoryPath -Force -ErrorAction Stop
            if (-not [string]::IsNullOrEmpty([string]$sourceDirectory.LinkType) -or
                -not [string]::IsNullOrEmpty([string]$destinationDirectory.LinkType)) {
                continue
            }
            $entries = [System.IO.Directory]::GetFileSystemEntries($sourceDirectoryPath)
            if ($entries.Length -eq 0) {
                Remove-Item -LiteralPath $sourceDirectoryPath -Force -ErrorAction Stop
                $deletedCount++
            }
        }
        catch {
            $failedDirectories.Add([pscustomobject]@{
                    RelativePath = $relativeDirectory
                    Message      = $_.Exception.Message
                })
        }
    }
    [pscustomobject]@{
        DeletedCount      = $deletedCount
        FailedDirectories = @($failedDirectories.ToArray())
    }
}
