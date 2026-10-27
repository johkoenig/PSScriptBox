<#
.SYNOPSIS
    Provides the media backup discovery helper.

.DESCRIPTION
    Defines Get-EligibleMediaBackup, which finds eligible original media
    backups and their processed files.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

. (Join-Path $PSScriptRoot '..\..\common\internal\Get-EligibleOriginalBackup.ps1')

<#
.SYNOPSIS
    Finds eligible original media backups.

.DESCRIPTION
    Searches recursively for _orig MOV, MP4, JPG, and JPEG backups and pairs
    them with the processed file in the same folder. MOV backups match MP4
    outputs; all other supported extensions match the same extension.

.PARAMETER RootPath
    Folder to search recursively.

.OUTPUTS
    PSCustomObject with BackupFile and ProcessedPath properties.
#>
function Get-EligibleMediaBackup
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RootPath)

    Get-EligibleOriginalBackup -RootPath $RootPath -Extensions @('.mov', '.mp4', '.jpg', '.jpeg') -ProcessedExtensionMap @{ '.mov' = '.mp4' }
}
