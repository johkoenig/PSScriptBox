<#
.SYNOPSIS
    Writes confirmed recommended Git settings to the target scope.

.DESCRIPTION
    Defines Set-RecommendedGitSetting. For each change the function reads the
    current value and either skips it, keeps it when it is unchanged, or writes
    the new value. The console messages are produced by the calling script.

.NOTES
    Dependencies: Get-GitConfigValue, Set-GitConfigValue, and common\internal\Get-LocalizedText.ps1 loaded by the caller.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Applies recommended setting changes.

.DESCRIPTION
    Each change has a Key and a Value. A null Value means the user skipped the
    setting. A value equal to the current one (case-sensitive) is preserved and
    not rewritten. Any other value is written with Set-GitConfigValue.

.PARAMETER Changes
    Objects with Key and Value properties. Value is $null to skip.

.PARAMETER Scope
    Local or Global.

.PARAMETER Repository
    Root path of the repository when the scope is Local.

.PARAMETER Language
    Language code used for error messages from the git helpers.

.PARAMETER MessagesPath
    Message catalog hashtable passed to the git helpers.

.OUTPUTS
    PSCustomObject[] with Key, Status ('Skipped', 'Preserved', 'Configured',
    'WouldConfigure', or 'Declined'), Value, and Current properties.
#>
function Set-RecommendedGitSetting
{
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [AllowEmptyCollection()][object[]] $Changes = @(),
        [Parameter(Mandatory)][ValidateSet('Local', 'Global')][string] $Scope,
        [string] $Repository,
        [string] $Language = 'en',
        [string]$MessagesPath = ''
    )

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($change in $Changes) {
        $current = Get-GitConfigValue -Key $change.Key -Scope $Scope -Repository $Repository -Language $Language -MessagesPath $MessagesPath
        if ($null -eq $change.Value) {
            $status = 'Skipped'
        }
        elseif ($change.Value -ceq $current) {
            $status = 'Preserved'
        }
        else {
            $action = Get-LocalizedText -Text 'Set Git configuration value {0} to {1}' `
                -Arguments @($change.Key, $change.Value) -Language $Language -MessagesPath $MessagesPath
            if ( $PSCmdlet.ShouldProcess("$Scope $( $change.Key )", $action))
            {
                Set-GitConfigValue -Key $change.Key -Value $change.Value -Scope $Scope `
                    -Repository $Repository -Language $Language -MessagesPath $MessagesPath `
                    -Confirm:$false -WhatIf:$false | Out-Null
                $status = 'Configured'
            }
            elseif ($WhatIfPreference)
            {
                $status = 'WouldConfigure'
            }
            else
            {
                $status = 'Declined'
            }
        }
        $results.Add([pscustomobject]@{
                Key     = $change.Key
                Status  = $status
                Value   = $change.Value
                Current = $current
            })
    }
    return $results.ToArray()
}
