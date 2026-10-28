<#
.SYNOPSIS
    Finds MOV videos paired with same-name JPG still images.

.DESCRIPTION
    Defines Get-LivePhotoVideoCandidate, which recursively finds MOV files
    with a same-name JPG in the same directory.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Gets MOV files paired with JPG still images.

.DESCRIPTION
    Searches recursively for MOV files and includes a candidate only when a
    same-base-name JPG file exists in the MOV file's directory.

.PARAMETER RootPath
    Folder to search recursively.

.OUTPUTS
    PSCustomObject with VideoFile and PhotoFile properties.
#>
function Get-LivePhotoVideoCandidate
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RootPath)

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container))
    {
        throw "The specified folder was not found: $RootPath"
    }

    $directory = Get-Item -LiteralPath $RootPath -ErrorAction Stop
    $videoFiles = Get-ChildItem -LiteralPath $directory.FullName -Filter '*.mov' -File -Recurse
    foreach ($videoFile in $videoFiles)
    {
        $photoPath = Join-Path $videoFile.DirectoryName ($videoFile.BaseName + '.jpg')
        if (Test-Path -LiteralPath $photoPath -PathType Leaf)
        {
            [pscustomobject]@{
                VideoFile = $videoFile
                PhotoFile = Get-Item -LiteralPath $photoPath -ErrorAction Stop
            }
        }
    }
}
