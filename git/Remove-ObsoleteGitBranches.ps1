<#
.SYNOPSIS
Removes obsolete local Git branches from the repository at the current location.

.DESCRIPTION
Protects the local main branch and the currently checked-out branch. A branch is
considered obsolete when it is not ahead of local main, is not ahead of its
available upstream, or is fully merged into the current branch. Branch analysis
and removal do not check out branches or modify working-tree files.

.PARAMETER EnglishOutput
Forces English console output regardless of the Windows UI language.

.PARAMETER WhatIf
Shows obsolete branches that would be removed without deleting them.

.EXAMPLE
.\Remove-ObsoleteGitBranches.ps1
Removes obsolete branches without prompting.

.EXAMPLE
.\Remove-ObsoleteGitBranches.ps1 -WhatIf

.NOTES
Dependencies: Git for Windows. If Git is missing, the script reports
installation guidance and exits.
Contributors:
- Johannes Koenig <dev@jokoenig.de>
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'This user-facing script provides localized, color-coded console output.'
)]
[CmdletBinding()]
param(
    [switch]$EnglishOutput,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'internal\Invoke-GitCommand.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-ObsoleteGitBranches.ps1')
. (Join-Path $PSScriptRoot 'internal\Remove-GitBranch.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-LocalizedText.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-MissingDependencyReport.ps1')

$script:Language = if (-not $EnglishOutput -and [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'de')
{
    'de'
}
else
{
    'en'
}
$script:Messages = if ($script:Language -eq 'de')
{
    Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1')
}
else
{
    @{ }
}

$headerLines = @(
    '       .-------------------------------------------.'
    '      /                                           /|'
    '     /___________________________________________/ |'
    '     |  .-------------------------------------.  | |'
    '     |  | OBSOLETE GIT BRANCH CLEANUP         |  | |'
    '     |  | PROTECT MAIN / CURRENT BRANCH       |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)
Write-Host ''
foreach ($headerLine in $headerLines)
{
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText -Text '  Removes obsolete local branches without changing the working tree.' -Language $script:Language -Messages $script:Messages) -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text '  Supports preview; removal runs without confirmation.' -Language $script:Language -Messages $script:Messages) -ForegroundColor Cyan
Write-Host ''

$gitCommand = Get-Command -Name 'git.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
if ($null -eq $gitCommand)
{
    $report = Get-MissingDependencyReport -Dependency 'Git for Windows' `
        -Guidance (Get-LocalizedText -Text 'Install Git for Windows from https://git-scm.com/download/win, or run: choco install git.install -y.' `
            -Language $script:Language -Messages $script:Messages) `
        -MessageTemplate (Get-LocalizedText -Text 'Missing dependency: {0}' `
            -Language $script:Language -Messages $script:Messages)
    Write-Host $report.Message -ForegroundColor Yellow
    Write-Host "  $( $report.Guidance )"
    exit 1
}

$failedBranches = [System.Collections.Generic.List[object]]::new()
$removedCount = 0
$previewedCount = 0
$branchCount = 0
$candidateCount = 0

try
{
    Write-Host (Get-LocalizedText -Text '=== Obsolete Git branches: processing started ===' -Language $script:Language -Messages $script:Messages) -ForegroundColor Cyan

    $invocationPath = (Get-Location).Path
    $repositoryRoot = (Invoke-GitCommand -Repository $invocationPath -Arguments @(
        'rev-parse',
        '--show-toplevel'
    ) -Language $script:Language -Messages $script:Messages | Select-Object -First 1).Trim()

    $branchState = Get-ObsoleteGitBranches -Repository $repositoryRoot -MainBranch 'main' -Language $script:Language -Messages $script:Messages
    $branchCount = $branchState.Branches.Count
    $candidateBranches = @($branchState.Branches | Where-Object { $_.IsObsolete })
    $candidateCount = $candidateBranches.Count
    $currentBranchName = if ($branchState.CurrentBranchRef -eq 'HEAD')
    {
        'detached HEAD'
    }
    else
    {
        $branchState.CurrentBranchRef.Substring('refs/heads/'.Length)
    }

    Write-Host ((Get-LocalizedText -Text 'Repository: {0}' -Language $script:Language -Messages $script:Messages) -f $repositoryRoot)
    Write-Host ((Get-LocalizedText -Text 'Current branch: {0}' -Language $script:Language -Messages $script:Messages) -f $currentBranchName)
    Write-Host ((Get-LocalizedText -Text 'Local branches: {0}' -Language $script:Language -Messages $script:Messages) -f $branchCount)
    Write-Host ((Get-LocalizedText -Text 'Obsolete candidates: {0}' -Language $script:Language -Messages $script:Messages) -f $candidateCount)

    if ($candidateCount -eq 0)
    {
        Write-Host (Get-LocalizedText -Text 'Nothing to remove; no obsolete local branches were found.' -Language $script:Language -Messages $script:Messages) -ForegroundColor Green
    }

    for ($index = 0; $index -lt $candidateBranches.Count; $index++) {
        $branch = $candidateBranches[$index]
        Write-Host ''
        Write-Host ((Get-LocalizedText -Text '--- Branch {0}/{1}: {2} ---' -Language $script:Language -Messages $script:Messages) -f ($index + 1), $candidateCount, $branch.Name) -ForegroundColor Cyan
        Write-Host ((Get-LocalizedText -Text 'Reasons: {0}' -Language $script:Language -Messages $script:Messages) -f ($branch.Reasons -join '; '))

        if ($WhatIf)
        {
            $previewedCount++
            Write-Host ((Get-LocalizedText -Text 'Would remove: {0}' -Language $script:Language -Messages $script:Messages) -f $branch.Name) -ForegroundColor Yellow
            continue
        }

        try
        {
            $null = Remove-GitBranch -Repository $repositoryRoot -Name $branch.Name -Ref $branch.Ref -ExpectedObjectId $branch.ObjectId -Language $script:Language -Messages $script:Messages
            $removedCount++
            Write-Host ((Get-LocalizedText -Text 'Removed: {0}' -Language $script:Language -Messages $script:Messages) -f $branch.Name) -ForegroundColor Green
        }
        catch
        {
            $reason = $_.Exception.Message
            $failedBranches.Add([pscustomobject]@{
                Name = $branch.Name
                Reason = $reason
            })
            $message = Get-LocalizedText -Text "Could not remove branch '{0}': {1}" -Language $script:Language -Messages $script:Messages
            Write-Warning ($message -f $branch.Name, $reason)
        }
    }

    Write-Host ''
    Write-Host (Get-LocalizedText -Text '=== Summary ===' -Language $script:Language -Messages $script:Messages) -ForegroundColor Cyan
    Write-Host ((Get-LocalizedText -Text 'Repository: {0}' -Language $script:Language -Messages $script:Messages) -f $repositoryRoot)
    Write-Host ((Get-LocalizedText -Text 'Branches checked: {0}; obsolete candidates: {1}' -Language $script:Language -Messages $script:Messages) -f $branchCount, $candidateCount)
    Write-Host ((Get-LocalizedText -Text 'Removed: {0}, previewed: {1}, failed: {2}' -Language $script:Language -Messages $script:Messages) -f $removedCount, $previewedCount, $failedBranches.Count)
    Write-Host (Get-LocalizedText -Text 'Failed branches:' -Language $script:Language -Messages $script:Messages)

    if ($failedBranches.Count -eq 0)
    {
        Write-Host '  None.'
    }
    else
    {
        foreach ($failedBranch in $failedBranches)
        {
            Write-Host ("  - {0} ({1})" -f $failedBranch.Name, $failedBranch.Reason) -ForegroundColor Yellow
        }
    }

    if ($failedBranches.Count -gt 0)
    {
        exit 1
    }
}
catch
{
    $message = Get-LocalizedText -Text 'Fatal error: {0}' -Language $script:Language -Messages $script:Messages
    Write-Host ($message -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
