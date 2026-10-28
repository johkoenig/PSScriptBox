<#
.SYNOPSIS
    Provides the special user folder path lookup for the Nextcloud scripts.

.DESCRIPTION
    Defines Get-UserSpecialFolderPath. Has no dependencies on other helpers.
    The Windows lookup is isolated here so that Get-UserFolder can be tested
    with explicit path values.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Resolves the Windows special folder paths for the supported user folders.

.DESCRIPTION
    Returns a hashtable keyed by folder name (Desktop, Documents, Pictures,
    Music, Videos). Values are the paths reported by the Windows known-folder
    API, so redirected and localized folders are resolved. Missing folders
    yield an empty string.

.OUTPUTS
    System.Collections.Hashtable. Folder name to absolute path.
#>
function Get-UserSpecialFolderPath
{
    [CmdletBinding()]
    param()

    $specialFolders = @{
        Desktop   = [System.Environment+SpecialFolder]::DesktopDirectory
        Documents = [System.Environment+SpecialFolder]::MyDocuments
        Pictures  = [System.Environment+SpecialFolder]::MyPictures
        Music     = [System.Environment+SpecialFolder]::MyMusic
        Videos    = [System.Environment+SpecialFolder]::MyVideos
    }
    $paths = @{}
    foreach ($name in $specialFolders.Keys) {
        $paths[$name] = [Environment]::GetFolderPath($specialFolders[$name])
    }
    return $paths
}
