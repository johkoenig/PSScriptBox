<#
.SYNOPSIS
    Finds supported media files for date restoration.

.DESCRIPTION
    Defines Get-MediaDateInputFiles, which recursively discovers the media
    formats supported for date restoration.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Uses Get-LocalizedText.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Gets supported media files under a folder.

.DESCRIPTION
    Recursively discovers supported media files. Hidden files are not included.

.PARAMETER RootPath
    Folder to search recursively.

.PARAMETER UiLanguage
    Language of error messages: 'de' selects German, anything else English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.OUTPUTS
    PSCustomObject with Files (System.IO.FileInfo[]) and BasePath (string).
#>
function Get-MediaDateInputFiles
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RootPath,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{ }
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }
    if (-not (Test-Path -LiteralPath $RootPath -PathType Container))
    {
        throw (Get-LocalizedText @localization -Text 'The selected path is not a folder: {0}' -Arguments @($RootPath))
    }

    $directory = Get-Item -LiteralPath $RootPath -ErrorAction Stop
    $extensions = @('.jpg', '.jpeg', '.png', '.mp4', '.mov', '.avi', '.mkv', '.gif', '.heic', '.webp', '.3gp', '.m4v')
    $files = @(
    Get-ChildItem -LiteralPath $directory.FullName -File -Recurse |
            Where-Object { $extensions -contains $_.Extension } |
            Sort-Object -Property FullName
    )

    [pscustomobject]@{
        Files = $files
        BasePath = $directory.FullName
    }
}
