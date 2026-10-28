<#
.SYNOPSIS
    Filters identity sources into unique candidates for the Git configuration script.

.DESCRIPTION
    Defines Get-IdentityCandidate. The function trims and validates the source
    values, removes case-insensitive duplicates while keeping the first
    occurrence, and localizes the source labels.

.NOTES
    Dependencies: Test-IdentityValue and common\internal\Get-LocalizedText.ps1 loaded by the caller.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Collects unique, valid name or email candidates.

.DESCRIPTION
    Keeps the order of the input entries. An entry is dropped when its value is
    empty or invalid for the key, or when an earlier entry has the same value
    (case-insensitive). The source label is localized with the given language and catalog.

.PARAMETER Key
    user.name or user.email.

.PARAMETER Entries
    Source entries from Get-IdentitySourceEntry with Value, Source, and
    SourceArguments properties.

.PARAMETER Language
    'de' selects German source labels; any other value selects English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    PSCustomObject[] with Value and Source properties. Empty when no entry is valid.
#>
function Get-IdentityCandidate
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('user.name', 'user.email')][string] $Key,
        [AllowEmptyCollection()][object[]] $Entries = @(),
        [string] $Language = 'en',
        [string]$MessagesPath = ''
    )

    $found = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Entries) {
        $value = [string] $entry.Value
        if ($null -eq $value) { continue }
        $value = $value.Trim()
        if (-not (Test-IdentityValue -Key $Key -Value $value)) { continue }
        if (@($found | Where-Object { $_.Value -ieq $value }).Count) { continue }
        $found.Add([pscustomobject]@{
                Value  = $value
                Source = Get-LocalizedText -Text $entry.Source -Arguments @($entry.SourceArguments) -Language $Language -MessagesPath $MessagesPath
            })
    }
    return $found.ToArray()
}
