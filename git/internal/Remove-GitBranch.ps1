<#
.SYNOPSIS
Removes a local Git branch after verifying its current commit.

.DESCRIPTION
Confirms that the branch still points to the commit observed during analysis
before deleting its local reference. It does not check out branches or alter
working-tree files.

.PARAMETER Repository
Repository path passed to Git's -C option.

.PARAMETER Name
Short name of the local branch to remove.

.PARAMETER Ref
Full local branch reference observed during analysis.

.PARAMETER ExpectedObjectId
Commit identifier observed during analysis.

.PARAMETER Language
'de' selects German error text; any other value selects English.

.PARAMETER MessagesPath
Path to the German message catalog.

.OUTPUTS
System.Management.Automation.PSCustomObject describing the removed branch.

.NOTES
Dependencies: Git and common\internal\Get-LocalizedText.ps1 loaded by the caller.
Contributors:
- Johannes Koenig <dev@jokoenig.de>
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors

<#
.SYNOPSIS
Removes a local Git branch after verifying its current commit.

.DESCRIPTION
Confirms that the branch still points to the commit observed during analysis
before deleting its local reference. It does not check out branches or alter
working-tree files.

.PARAMETER Repository
Repository path passed to Git's -C option.

.PARAMETER Name
Short name of the local branch to remove.

.PARAMETER Ref
Full local branch reference observed during analysis.

.PARAMETER ExpectedObjectId
Commit identifier observed during analysis.

.PARAMETER Language
'de' selects German error text; any other value selects English.

.PARAMETER MessagesPath
Path to the German message catalog.

.PARAMETER WhatIf
Simulates branch removal without changing the repository.

.PARAMETER Confirm
Prompts before removing the branch.

.OUTPUTS
System.Management.Automation.PSCustomObject with Name, Ref, and Status
('Removed', 'WhatIf', or 'Declined').
#>
function Remove-GitBranch
{
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Ref,

        [Parameter(Mandatory)]
        [string]$ExpectedObjectId,

        [string]$Language = 'en',

        [string]$MessagesPath = ''
    )

    $actualObjectId = (Invoke-GitCommand -Repository $Repository -Arguments @(
        'rev-parse',
        '--verify',
        $Ref
    ) -Language $Language -MessagesPath $MessagesPath | Select-Object -First 1).Trim()

    if ($actualObjectId -ne $ExpectedObjectId)
    {
        $message = Get-LocalizedText -Text 'Branch changed after analysis; refusing to remove it: {0}' -Language $Language -MessagesPath $MessagesPath
        throw ($message -f $Name)
    }

    $action = Get-LocalizedText -Text 'Remove local Git branch: {0}' `
        -Arguments @($Name) -Language $Language -MessagesPath $MessagesPath
    if (-not $PSCmdlet.ShouldProcess($Name, $action))
    {
        return [pscustomobject]@{
            Name = $Name
            Ref = $Ref
            Status = if ($WhatIfPreference)
            {
                'WhatIf'
            }
            else
            {
                'Declined'
            }
        }
    }

    $null = Invoke-GitCommand -Repository $Repository -Arguments @(
        'branch',
        '-D',
        '--',
        $Name
    ) -Language $Language -MessagesPath $MessagesPath

    [pscustomobject]@{
        Name = $Name
        Ref = $Ref
        Status = 'Removed'
    }
}
