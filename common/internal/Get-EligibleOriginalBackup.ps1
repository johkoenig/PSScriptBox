<#
.SYNOPSIS
    Finds original backups whose processed files exist.

.DESCRIPTION
    Defines Get-EligibleOriginalBackup, which searches recursively for files
    ending in _orig and pairs each backup with its processed file. Optional
    extension mappings support workflows that change file types.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Gets original backups with an existing processed counterpart.

.DESCRIPTION
    Searches a folder recursively, including hidden files, for files with a
    selected extension whose base name ends with _orig. A pair is returned only
    when the corresponding processed file exists in the same folder.

.PARAMETER RootPath
    Folder to search recursively.

.PARAMETER Extensions
    File extensions to consider for original backups, including the leading dot.

.PARAMETER ProcessedExtensionMap
    Optional map from an original backup extension to the processed file
    extension. Unmapped extensions use the same extension as the backup.

.OUTPUTS
    PSCustomObject with BackupFile and ProcessedPath properties.
#>
function Get-EligibleOriginalBackup
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RootPath,
        [Parameter(Mandatory)][string[]] $Extensions,
        [hashtable] $ProcessedExtensionMap = @{ }
    )

    $normalizedExtensions = @($Extensions | ForEach-Object { $_.ToLowerInvariant() })
    $originalFiles = @(Get-ChildItem -LiteralPath $RootPath -File -Recurse -Force |
            Where-Object {
                $normalizedExtensions -contains $_.Extension.ToLowerInvariant() -and
                        $_.BaseName -match '_orig$'
            })

    foreach ($originalFile in $originalFiles)
    {
        $processedBaseName = $originalFile.BaseName -replace '_orig$', ''
        $processedExtension = $originalFile.Extension
        $mappingKey = @(
        $ProcessedExtensionMap.Keys |
                Where-Object { [string]::Equals([string]$_, $originalFile.Extension, [System.StringComparison]::OrdinalIgnoreCase) } |
                Select-Object -First 1
        )
        if ($mappingKey.Count -gt 0)
        {
            $processedExtension = [string]$ProcessedExtensionMap[$mappingKey[0]]
        }

        $processedPath = Join-Path -Path $originalFile.DirectoryName -ChildPath ($processedBaseName + $processedExtension)
        if (Test-Path -LiteralPath $processedPath -PathType Leaf)
        {
            [pscustomobject]@{
                BackupFile = $originalFile
                ProcessedPath = $processedPath
            }
        }
    }
}
