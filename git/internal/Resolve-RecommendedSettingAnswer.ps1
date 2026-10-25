<#
.SYNOPSIS
    Interprets the answer to a recommended Git setting prompt.

.DESCRIPTION
    Defines Resolve-RecommendedSettingAnswer. The function maps the typed text
    to a skip, the default value, a listed option, or a custom value. The
    console prompt stays in the calling script.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Resolves the answer to a recommended setting prompt.

.DESCRIPTION
    '-' skips the setting. An empty answer selects the default. Otherwise a
    case-insensitive match against the options selects the option's canonical
    value. When custom values are allowed, any other text is accepted as is;
    if not, the answer is reported as invalid.

.PARAMETER Answer
    The typed text.

.PARAMETER Default
    Value used for an empty answer.

.PARAMETER Options
    Options from Get-RecommendedSettingOption with Value properties.

.PARAMETER AllowCustom
    Accept any text that matches no option.

.OUTPUTS
    PSCustomObject with Kind ('Skip', 'Value', or 'Invalid') and Value (null for Skip).
#>
function Resolve-RecommendedSettingAnswer {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string] $Answer,
        [AllowEmptyString()][string] $Default,
        [AllowEmptyCollection()][object[]] $Options = @(),
        [switch] $AllowCustom
    )

    $text = ([string] $Answer).Trim()
    if ($text -eq '-') { return [pscustomobject]@{ Kind = 'Skip'; Value = $null } }
    if ($text -eq '') { return [pscustomobject]@{ Kind = 'Value'; Value = $Default } }
    $match = @($Options | Where-Object { $_.Value -ieq $text }) | Select-Object -First 1
    if ($match) { return [pscustomobject]@{ Kind = 'Value'; Value = [string] $match.Value } }
    if ($AllowCustom) { return [pscustomobject]@{ Kind = 'Value'; Value = $text } }
    return [pscustomobject]@{ Kind = 'Invalid'; Value = $null }
}
