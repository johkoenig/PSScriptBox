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

.PARAMETER Messages
German message catalog keyed by the English source text.

.OUTPUTS
System.Management.Automation.PSCustomObject describing the removed branch.

.NOTES
Dependencies: Git and common\internal\Get-LocalizedText.ps1 loaded by the caller.
Contributors:
- Johannes Koenig <dev@jokoenig.de>
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors

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

.PARAMETER Messages
German message catalog keyed by the English source text.

.OUTPUTS
System.Management.Automation.PSCustomObject describing the removed branch.
#>
function Remove-GitBranch
{
    [CmdletBinding()]
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

        [hashtable]$Messages = @{ }
    )

    $actualObjectId = (Invoke-GitCommand -Repository $Repository -Arguments @(
        'rev-parse',
        '--verify',
        $Ref
    ) -Language $Language -Messages $Messages | Select-Object -First 1).Trim()

    if ($actualObjectId -ne $ExpectedObjectId)
    {
        $message = Get-LocalizedText -Text 'Branch changed after analysis; refusing to remove it: {0}' -Language $Language -Messages $Messages
        throw ($message -f $Name)
    }

    $null = Invoke-GitCommand -Repository $Repository -Arguments @(
        'branch',
        '-D',
        '--',
        $Name
    ) -Language $Language -Messages $Messages

    [pscustomobject]@{
        Name = $Name
        Ref = $Ref
    }
}
