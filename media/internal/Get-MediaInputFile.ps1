<#
.SYNOPSIS
    Provides video file discovery for the media optimizer.

.DESCRIPTION
    Defines Get-MediaInputFile, which resolves a supported video or JPEG file
    or folder of MOV, MP4, JPG, and JPEG files into a sorted list.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Uses Get-LocalizedText.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Gets supported media files from a path.

.DESCRIPTION
    Accepts one MOV, MP4, JPG, or JPEG file, or recursively discovers these
    formats in a folder. Files ending in _orig are excluded. The function
    never prompts.

.PARAMETER Path
    Path to a MOV, MP4, JPG, or JPEG file, or a folder. Surrounding quotation
    marks and environment variables are resolved.

.PARAMETER UiLanguage
    Language of error messages: 'de' selects German, anything else English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    PSCustomObject with Files (System.IO.FileInfo[]) and BasePath (string).
#>
function Get-MediaInputFile
{
    [CmdletBinding()]
    param(
        [string] $Path,
        [string] $UiLanguage = 'en',
        [string]$MessagesPath = ''
    )
    if ( [string]::IsNullOrWhiteSpace($Path))
    {
        throw (Get-LocalizedText -Text 'No path was entered.' -Language $UiLanguage -MessagesPath $MessagesPath)
    }

    $Path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (-not (Test-Path -LiteralPath $Path))
    {
        throw (Get-LocalizedText -Text 'Path not found: {0}' -Arguments @($Path) -Language $UiLanguage -MessagesPath $MessagesPath)
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer)
    {
        $files = @(
        foreach ($filter in @('*.mov', '*.mp4', '*.jpg', '*.jpeg'))
        {
            Get-ChildItem -LiteralPath $item.FullName -File -Filter $filter -Recurse
        }
        ) | Where-Object { $_.BaseName -notmatch '_orig$' } |
                Sort-Object -Property FullName
        $basePath = $item.FullName
    }
    else
    {
        if ($item.Extension -notin @('.mov', '.mp4', '.jpg', '.jpeg'))
        {
            throw (Get-LocalizedText -Text 'The selected file is not a supported media file (.mov, .mp4, .jpg, .jpeg).' -Language $UiLanguage -MessagesPath $MessagesPath)
        }
        $files = if ($item.BaseName -match '_orig$')
        {
            @()
        }
        else
        {
            @($item)
        }
        $basePath = $item.DirectoryName
    }

    [pscustomobject]@{ Files = @($files); BasePath = $basePath }
}
