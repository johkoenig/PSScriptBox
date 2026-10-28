<#
.SYNOPSIS
    Provides the original PDF backup discovery helper for the cleanup script.

.DESCRIPTION
    Defines Get-EligibleOriginalPdf, which finds _orig PDF backups whose
    processed PDF exists.

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
    Finds original PDF backups that have a processed PDF next to them.

.DESCRIPTION
    Searches a folder recursively, including hidden files, for PDF files whose
    base name ends with _orig. A match is returned only when the processed PDF
    with the same name without the _orig suffix exists as a file in the same
    folder. Makes no changes to the file system.

.PARAMETER RootPath
    Folder to search recursively.

.OUTPUTS
    System.IO.FileInfo. The eligible original PDF backups, or nothing when none
    match.
#>
function Get-EligibleOriginalPdf {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RootPath)

    foreach ($backup in Get-EligibleOriginalBackup -RootPath $RootPath -Extensions @('.pdf'))
    {
        $backup.BackupFile
    }
}
