<#
.SYNOPSIS
Finds local Git branches that meet an obsolescence rule.

.DESCRIPTION
Compares local branches with the local main branch, configured upstreams, and
the current commit without changing the repository or working tree.

.PARAMETER Repository
Repository path passed to Git's -C option.

.PARAMETER MainBranch
Name of the local main branch used for comparison and protection.

.PARAMETER Language
'de' selects German error text; any other value selects English.

.PARAMETER MessagesPath
Path to the German message catalog.

.OUTPUTS
System.Management.Automation.PSCustomObject containing branch assessments and
the current branch reference.

.NOTES
Dependencies: Git and common\internal\Get-LocalizedText.ps1 loaded by the caller.
Contributors:
- Johannes Koenig <dev@jokoenig.de>
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors

<#
.SYNOPSIS
Finds local Git branches that meet an obsolescence rule.

.DESCRIPTION
Compares local branches with the local main branch, configured upstreams, and
the current commit without changing the repository or working tree.

.PARAMETER Repository
Repository path passed to Git's -C option.

.PARAMETER MainBranch
Name of the local main branch used for comparison and protection.

.PARAMETER Language
'de' selects German error text; any other value selects English.

.PARAMETER MessagesPath
Path to the German message catalog.

.OUTPUTS
System.Management.Automation.PSCustomObject containing branch assessments and
the current branch reference.
#>
function Get-ObsoleteGitBranch
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [string]$MainBranch = 'main',

        [string]$Language = 'en',

        [string]$MessagesPath = ''
    )

    $branchLines = Invoke-GitCommand -Repository $Repository -Arguments @(
        'for-each-ref',
        '--format=%(refname)%09%(objectname)%09%(upstream)',
        'refs/heads'
    ) -Language $Language -MessagesPath $MessagesPath

    $branches = foreach ($line in $branchLines)
    {
        $fields = $line.Split([char]9)
        if ($fields.Count -ne 3 -or -not $fields[0].StartsWith('refs/heads/'))
        {
            $message = Get-LocalizedText -Text "Git returned invalid branch data: '{0}'" -Language $Language -MessagesPath $MessagesPath
            throw ($message -f $line)
        }

        [pscustomobject]@{
            Name = $fields[0].Substring('refs/heads/'.Length)
            Ref = $fields[0]
            ObjectId = $fields[1]
            Upstream = $fields[2]
        }
    }

    $mainRef = "refs/heads/$MainBranch"
    if (-not ($branches | Where-Object { $_.Ref -eq $mainRef }))
    {
        $message = Get-LocalizedText -Text "The main branch '{0}' was not found in this repository." -Language $Language -MessagesPath $MessagesPath
        throw ($message -f $MainBranch)
    }

    $currentRef = (Invoke-GitCommand -Repository $Repository -Arguments @(
        'rev-parse',
        '--symbolic-full-name',
        'HEAD'
    ) -Language $Language -MessagesPath $MessagesPath | Select-Object -First 1).Trim()

    $allRefs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($ref in (Invoke-GitCommand -Repository $Repository -Arguments @(
        'for-each-ref',
        '--format=%(refname)'
    ) -Language $Language -MessagesPath $MessagesPath))
    {
        $null = $allRefs.Add($ref)
    }

    $mergedRefs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($ref in (Invoke-GitCommand -Repository $Repository -Arguments @(
        'branch',
        '--merged',
        'HEAD',
        '--format=%(refname)'
    ) -Language $Language -MessagesPath $MessagesPath))
    {
        if ($ref)
        {
            $null = $mergedRefs.Add($ref)
        }
    }

    $branchAssessments = foreach ($branch in $branches)
    {
        $isProtected = $branch.Ref -eq $mainRef -or $branch.Ref -eq $currentRef
        $reasons = [System.Collections.Generic.List[string]]::new()

        if (-not $isProtected)
        {
            $aheadOfMain = (Invoke-GitCommand -Repository $Repository -Arguments @(
                'rev-list',
                '--count',
                "$mainRef..$( $branch.Ref )"
            ) -Language $Language -MessagesPath $MessagesPath | Select-Object -First 1).Trim()

            if ($aheadOfMain -notmatch '^\d+$')
            {
                $message = Get-LocalizedText -Text "Git returned an invalid commit count for '{0}': '{1}'" -Language $Language -MessagesPath $MessagesPath
                throw ($message -f $branch.Name, $aheadOfMain)
            }

            if ([long]$aheadOfMain -eq 0)
            {
                $reasons.Add((Get-LocalizedText -Text 'Not ahead of main' -Language $Language -MessagesPath $MessagesPath))
            }

            if ($branch.Upstream -and $allRefs.Contains($branch.Upstream))
            {
                $aheadOfUpstream = (Invoke-GitCommand -Repository $Repository -Arguments @(
                    'rev-list',
                    '--count',
                    "$( $branch.Upstream )..$( $branch.Ref )"
                ) -Language $Language -MessagesPath $MessagesPath | Select-Object -First 1).Trim()

                if ($aheadOfUpstream -notmatch '^\d+$')
                {
                    $message = Get-LocalizedText -Text "Git returned an invalid commit count for '{0}': '{1}'" -Language $Language -MessagesPath $MessagesPath
                    throw ($message -f $branch.Name, $aheadOfUpstream)
                }

                if ([long]$aheadOfUpstream -eq 0)
                {
                    $reasons.Add((Get-LocalizedText -Text 'Not ahead of upstream' -Language $Language -MessagesPath $MessagesPath))
                }
            }

            if ( $mergedRefs.Contains($branch.Ref))
            {
                $reasons.Add((Get-LocalizedText -Text 'Fully merged into the current branch' -Language $Language -MessagesPath $MessagesPath))
            }
        }

        [pscustomobject]@{
            Name = $branch.Name
            Ref = $branch.Ref
            ObjectId = $branch.ObjectId
            Upstream = $branch.Upstream
            IsProtected = $isProtected
            IsObsolete = $reasons.Count -gt 0
            Reasons = @($reasons.ToArray())
        }
    }

    [pscustomobject]@{
        MainBranchRef = $mainRef
        CurrentBranchRef = $currentRef
        Branches = @($branchAssessments)
    }
}
