<#
.SYNOPSIS
    Interprets the answer to the identity candidate menu for the Git configuration script.

.DESCRIPTION
    Defines Select-IdentityValue. The function maps the typed selection to a
    candidate, to the custom-entry option, or reports an invalid answer. The
    console prompt itself stays in the calling script.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Interprets a candidate selection.

.DESCRIPTION
    Candidates are numbered from 1; the number after the last candidate selects
    the custom-entry option. An empty answer selects candidate 1, which is the
    existing setting when one exists.

.PARAMETER Candidates
    Candidates with Value and Source properties, as returned by Get-IdentityCandidate.

.PARAMETER Answer
    The typed selection.

.OUTPUTS
    PSCustomObject with Kind ('Candidate', 'Custom', or 'Invalid') and Value
    (the chosen candidate value for 'Candidate', otherwise empty).
#>
function Select-IdentityValue {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]] $Candidates = @(),
        [AllowEmptyString()][string] $Answer
    )

    $text = ([string] $Answer).Trim()
    if ($text -eq '') { $text = '1' }
    $number = 0
    if (-not [int]::TryParse($text, [ref] $number) -or $number -lt 1 -or $number -gt ($Candidates.Count + 1)) {
        return [pscustomobject]@{ Kind = 'Invalid'; Value = '' }
    }
    if ($number -le $Candidates.Count) {
        return [pscustomobject]@{ Kind = 'Candidate'; Value = [string] $Candidates[$number - 1].Value }
    }
    return [pscustomobject]@{ Kind = 'Custom'; Value = '' }
}
