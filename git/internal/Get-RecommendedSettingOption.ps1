<#
.SYNOPSIS
    Builds the selectable options for a recommended Git setting.

.DESCRIPTION
    Defines Get-RecommendedSettingOption. The function returns the catalog
    options and, when the current value is not among them, prepends it so the
    user can keep an existing value unchanged.

.NOTES
    Dependencies: common\internal\Get-LocalizedText.ps1 loaded by the caller.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Returns the options offered for one recommended setting.

.DESCRIPTION
    The current value is inserted first with the label "Current value
    (unchanged)" when it is non-empty and not one of the catalog values. The
    comparison is case-sensitive, because Git values such as "true" and "True"
    can be stored differently. Option texts are localized with the given
    language and catalog.

.PARAMETER Options
    Catalog options with Value and Text properties.

.PARAMETER Current
    Value currently set in the target scope; empty when unset.

.PARAMETER Language
    'de' selects German option texts; any other value selects English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.OUTPUTS
    PSCustomObject[] with Value, Text, and IsCurrent properties.
#>
function Get-RecommendedSettingOption {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]] $Options = @(),
        [AllowEmptyString()][string] $Current,
        [string] $Language = 'en',
        [hashtable] $Messages = @{}
    )

    $result = [System.Collections.Generic.List[object]]::new()
    if ($Current -and -not @($Options | Where-Object { $_.Value -ceq $Current }).Count) {
        $result.Add([pscustomobject]@{
                Value     = $Current
                Text      = Get-LocalizedText -Text 'Current value (unchanged)' -Language $Language -Messages $Messages
                IsCurrent = $true
            })
    }
    foreach ($option in $Options) {
        $result.Add([pscustomobject]@{
                Value     = [string] $option.Value
                Text      = Get-LocalizedText -Text ([string] $option.Text) -Language $Language -Messages $Messages
                IsCurrent = $false
            })
    }
    return $result.ToArray()
}
