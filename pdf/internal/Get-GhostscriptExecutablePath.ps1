<#
.SYNOPSIS
    Provides the Ghostscript lookup helper for the PDF scripts.

.DESCRIPTION
    Defines Get-GhostscriptExecutablePath, which searches for the Ghostscript
    console executable under its Windows and generic names.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Finds the Ghostscript console executable.

.DESCRIPTION
    Tries gswin64c, gswin32c, and gs in that order and returns the first path
    found in the current PATH.

.OUTPUTS
    System.String or null. The Ghostscript path, or null when it is not available.
#>
function Get-GhostscriptExecutablePath {
    [CmdletBinding()]
    param()

    foreach ($name in @('gswin64c', 'gswin32c', 'gs')) {
        $path = Get-ExecutablePath -Name $name
        if ($path) { return $path }
    }
    return $null
}
