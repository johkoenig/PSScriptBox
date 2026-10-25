<#
.SYNOPSIS
    Provides the special user folder resolution for the Nextcloud scripts.

.DESCRIPTION
    Defines Get-UserFolders. Requires Get-LocalizedText, which is provided by
    common\internal\Get-LocalizedText.ps1 and must be dot-sourced first. Folder paths
    are passed in from Get-UserSpecialFolderPaths.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Resolves selected Windows special user folders.

.DESCRIPTION
    Uses Windows-known folder locations so redirected folders and localized
    profile layouts are discovered from the current user's operating system.
    The Pictures folder is mapped to the Photos target name.

.PARAMETER Names
    Special user folder names requested for processing.

.PARAMETER FolderPaths
    Hashtable mapping each folder name to its resolved path, as returned by
    Get-UserSpecialFolderPaths. Names without a usable path are skipped.

.OUTPUTS
    PSCustomObject[] with source Name, SourcePath, and target TargetName.
#>
function Get-UserFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]] $Names,
        [Parameter(Mandatory)][hashtable] $FolderPaths
    )

    foreach ($name in $Names) {
        $sourcePath = [string]$FolderPaths[$name]
        if ([string]::IsNullOrWhiteSpace($sourcePath) -or
            -not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
            Write-Warning (Get-LocalizedText -Text 'The Windows folder could not be found and will be skipped: {0}' -Arguments @($name))
            continue
        }
        [pscustomobject]@{
            Name       = $name
            SourcePath = [System.IO.Path]::GetFullPath($sourcePath)
            TargetName = if ($name -eq 'Pictures') { 'Photos' } else { $name }
        }
    }
}
