<#
.SYNOPSIS
    Provides the file read-access check for the Nextcloud scripts.

.DESCRIPTION
    Defines Test-FileReadAccess. Requires Get-LocalizedText.ps1 from the same
    folder.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Checks whether a file can be opened for reading.

.DESCRIPTION
    Opens an existing file for read access without reading or changing its
    contents. The file is opened with shared read, write, and delete access so
    that files held open by other programs, such as the sync client, are only
    reported when the operating system refuses access.

.PARAMETER Path
    Existing file to check.

.PARAMETER Language
    'de' selects German problem texts; any other value selects English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.OUTPUTS
    PSCustomObject with Path and Reason for each problem. Nothing is returned
    when the file can be opened.
#>
function Test-FileReadAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Path,
        [string] $Language = 'en',
        [hashtable] $Messages = @{}
    )

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    }
    catch [System.UnauthorizedAccessException] {
        [pscustomobject]@{
            Path = $Path
            Reason = (Get-LocalizedText -Text 'No read permission on file' -Language $Language -Messages $Messages)
        }
    }
    catch [System.IO.IOException] {
        [pscustomobject]@{
            Path = $Path
            Reason = (Get-LocalizedText -Text 'File cannot be read: {0}' -Arguments @($_.Exception.Message) `
                    -Language $Language -Messages $Messages)
        }
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}
