# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>
<#
.SYNOPSIS
    Tests local Git branch obsolescence detection.

.DESCRIPTION
    Creates temporary Git repositories to verify the branch rules and ensure
    analysis does not modify uncommitted working-tree files.

.NOTES
    Dependencies: Pester 5 or later, Git for Windows. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Invoke-GitCommand.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-ObsoleteGitBranches.ps1')

    $script:Language = 'en-US'
    $script:Messages = @{ }

    function Invoke-TestGit
    {
        param(
            [Parameter(Mandatory)]
            [string]$Repository,

            [Parameter(Mandatory)]
            [string[]]$Arguments
        )

        Invoke-GitCommand -Repository $Repository -Arguments $Arguments
    }

    function Add-TestCommit
    {
        param(
            [Parameter(Mandatory)]
            [string]$Repository,

            [Parameter(Mandatory)]
            [string]$FileName,

            [Parameter(Mandatory)]
            [string]$Content
        )

        [System.IO.File]::WriteAllText((Join-Path $Repository $FileName), $Content)
        $null = Invoke-TestGit -Repository $Repository -Arguments @('add', '--', $FileName)
        $null = Invoke-TestGit -Repository $Repository -Arguments @('commit', '--quiet', '-m', "Add $FileName")
    }

    function New-BranchRulesRepository
    {
        $repository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $repository
        $null = Invoke-GitCommand -Repository $repository -Arguments @('init', '--quiet')
        $null = Invoke-TestGit -Repository $repository -Arguments @('checkout', '--quiet', '-b', 'main')
        $null = Invoke-TestGit -Repository $repository -Arguments @('config', 'user.name', 'Test User')
        $null = Invoke-TestGit -Repository $repository -Arguments @('config', 'user.email', 'test@example.invalid')
        Add-TestCommit -Repository $repository -FileName 'base.txt' -Content 'base'
        $baseObjectId = (Invoke-TestGit -Repository $repository -Arguments @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()

        $null = Invoke-TestGit -Repository $repository -Arguments @('branch', 'behind-main', $baseObjectId)
        $null = Invoke-TestGit -Repository $repository -Arguments @('checkout', '--quiet', '-b', 'current', 'main')
        Add-TestCommit -Repository $repository -FileName 'current.txt' -Content 'current'
        $currentObjectId = (Invoke-TestGit -Repository $repository -Arguments @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()
        $null = Invoke-TestGit -Repository $repository -Arguments @('branch', 'merged-current', $currentObjectId)

        $null = Invoke-TestGit -Repository $repository -Arguments @('checkout', '--quiet', '-b', 'upstream-synced', $baseObjectId)
        Add-TestCommit -Repository $repository -FileName 'upstream.txt' -Content 'upstream'
        $upstreamObjectId = (Invoke-TestGit -Repository $repository -Arguments @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()
        $null = Invoke-TestGit -Repository $repository -Arguments @('remote', 'add', 'origin', 'https://example.invalid/repository.git')
        $null = Invoke-TestGit -Repository $repository -Arguments @('update-ref', 'refs/remotes/origin/upstream-synced', $upstreamObjectId)
        $null = Invoke-TestGit -Repository $repository -Arguments @('config', 'branch.upstream-synced.remote', 'origin')
        $null = Invoke-TestGit -Repository $repository -Arguments @('config', 'branch.upstream-synced.merge', 'refs/heads/upstream-synced')

        $null = Invoke-TestGit -Repository $repository -Arguments @('checkout', '--quiet', '-b', 'ahead-only', $baseObjectId)
        Add-TestCommit -Repository $repository -FileName 'ahead.txt' -Content 'ahead'
        $null = Invoke-TestGit -Repository $repository -Arguments @('checkout', '--quiet', 'main')
        Add-TestCommit -Repository $repository -FileName 'main.txt' -Content 'main'
        $null = Invoke-TestGit -Repository $repository -Arguments @('checkout', '--quiet', 'current')

        return $repository
    }
}

Describe 'Get-ObsoleteGitBranches' {
    It 'detects each obsolescence rule, protects main and current, and leaves working-tree changes untouched' {
        $repository = New-BranchRulesRepository
        $untrackedPath = Join-Path $repository 'uncommitted.txt'
        [System.IO.File]::WriteAllText($untrackedPath, 'keep this file')

        $state = Get-ObsoleteGitBranches -Repository $repository
        $branchMap = @{ }
        foreach ($branch in $state.Branches)
        {
            $branchMap[$branch.Name] = $branch
        }

        $branchMap['main'].IsProtected | Should -BeTrue
        $branchMap['main'].IsObsolete | Should -BeFalse
        $branchMap['current'].IsProtected | Should -BeTrue
        $branchMap['current'].IsObsolete | Should -BeFalse

        $branchMap['behind-main'].IsObsolete | Should -BeTrue
        $branchMap['behind-main'].Reasons | Should -Contain 'Not ahead of main'
        $branchMap['upstream-synced'].IsObsolete | Should -BeTrue -Because "upstream '$( $branchMap['upstream-synced'].Upstream )' with reasons '$( $branchMap['upstream-synced'].Reasons -join ', ' )'"
        $branchMap['upstream-synced'].Reasons | Should -Contain 'Not ahead of upstream'
        $branchMap['merged-current'].IsObsolete | Should -BeTrue
        $branchMap['merged-current'].Reasons | Should -Contain 'Fully merged into the current branch'
        $branchMap['ahead-only'].IsObsolete | Should -BeFalse

        [System.IO.File]::ReadAllText($untrackedPath) | Should -Be 'keep this file'
        (Invoke-TestGit -Repository $repository -Arguments @('branch', '--show-current') | Select-Object -First 1).Trim() | Should -Be 'current'
    }

    It 'fails clearly when the local main branch is missing' {
        $repository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $repository
        $null = Invoke-GitCommand -Repository $repository -Arguments @('init', '--quiet')

        { Get-ObsoleteGitBranches -Repository $repository } |
                Should -Throw -ExpectedMessage "The main branch 'main' was not found*"
    }
}
