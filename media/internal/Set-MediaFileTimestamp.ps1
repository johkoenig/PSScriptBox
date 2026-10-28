<#
.SYNOPSIS
    Sets the file-system timestamps of a media file.

.DESCRIPTION
    Defines Set-MediaFileTimestamp, which restores creation, last-write, and
    last-access timestamps using UTC values captured from the source file.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7 and
    common\internal\Get-LocalizedText.ps1 loaded by the caller.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Restores the source file's file-system timestamps.

.DESCRIPTION
    Sets the three file-system timestamps exposed by .NET. NTFS change time is
    not writable through these APIs.

.PARAMETER Path
    Path to the file whose timestamps are set.

.PARAMETER CreationTimeUtc
    Original creation timestamp in UTC.

.PARAMETER LastWriteTimeUtc
    Original last-write timestamp in UTC.

.PARAMETER LastAccessTimeUtc
    Original last-access timestamp in UTC.

.PARAMETER UiLanguage
    Language of confirmation text: 'de' selects German, anything else English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.OUTPUTS
None.
#>
function Set-MediaFileTimestamp
{
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][datetime] $CreationTimeUtc,
        [Parameter(Mandatory)][datetime] $LastWriteTimeUtc,
        [Parameter(Mandatory)][datetime] $LastAccessTimeUtc,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{ }
    )

    $action = Get-LocalizedText -Text 'Restore source file timestamps' `
        -Language $UiLanguage -Messages $Messages
    if (-not $PSCmdlet.ShouldProcess($Path, $action))
    {
        return
    }

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    [System.IO.File]::SetCreationTimeUtc($resolvedPath, $CreationTimeUtc)
    [System.IO.File]::SetLastWriteTimeUtc($resolvedPath, $LastWriteTimeUtc)
    [System.IO.File]::SetLastAccessTimeUtc($resolvedPath, $LastAccessTimeUtc)
}
