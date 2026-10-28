# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>
<#
.SYNOPSIS
    Tests guarded removal of local Git branches.

.DESCRIPTION
    Uses temporary repositories to verify that branch deletion checks the
    expected commit and does not change the checked-out branch or working tree.

.NOTES
    Dependencies: Pester 5 or later, Git for Windows. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Invoke-GitCommand.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Remove-GitBranch.ps1')
    $script:Language = 'en-US'
    $script:MessagesPath = ''

    function New-BranchRemovalRepository
    {
        $repository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $repository
        $null = Invoke-GitCommand -Repository $repository -Arguments @('init', '--quiet')
        $null = Invoke-GitCommand -Repository $repository -Arguments @('checkout', '--quiet', '-b', 'main')
        $null = Invoke-GitCommand -Repository $repository -Arguments @('config', 'user.name', 'Test User')
        $null = Invoke-GitCommand -Repository $repository -Arguments @('config', 'user.email', 'test@example.invalid')
        [System.IO.File]::WriteAllText((Join-Path $repository 'base.txt'), 'base')
        $null = Invoke-GitCommand -Repository $repository -Arguments @('add', '--', 'base.txt')
        $null = Invoke-GitCommand -Repository $repository -Arguments @('commit', '--quiet', '-m', 'Initial commit')
        $objectId = (Invoke-GitCommand -Repository $repository -Arguments @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()
        $null = Invoke-GitCommand -Repository $repository -Arguments @('branch', 'candidate', $objectId)
        return [pscustomobject]@{
            Repository = $repository
            ObjectId = $objectId
        }
    }
}

Describe 'Remove-GitBranch' {
    It 'removes the expected branch without changing the current branch or uncommitted files' {
        $fixture = New-BranchRemovalRepository
        $modifiedPath = Join-Path $fixture.Repository 'base.txt'
        [System.IO.File]::WriteAllText($modifiedPath, 'keep this unstaged change')
        $untrackedPath = Join-Path $fixture.Repository 'uncommitted.txt'
        [System.IO.File]::WriteAllText($untrackedPath, 'keep this file')

        $result = Remove-GitBranch -Repository $fixture.Repository -Name 'candidate' -Ref 'refs/heads/candidate' -ExpectedObjectId $fixture.ObjectId

        $result.Name | Should -Be 'candidate'
        (Invoke-GitCommand -Repository $fixture.Repository -Arguments @('branch', '--list', 'candidate') | Out-String).Trim() | Should -BeNullOrEmpty
        (Invoke-GitCommand -Repository $fixture.Repository -Arguments @('branch', '--show-current') | Select-Object -First 1).Trim() | Should -Be 'main'
        [System.IO.File]::ReadAllText($modifiedPath) | Should -Be 'keep this unstaged change'
        [System.IO.File]::ReadAllText($untrackedPath) | Should -Be 'keep this file'
    }

    It 'refuses to remove a branch whose commit no longer matches the analysis' {
        $fixture = New-BranchRemovalRepository
        $wrongObjectId = '0000000000000000000000000000000000000000'

        {
            Remove-GitBranch -Repository $fixture.Repository -Name 'candidate' -Ref 'refs/heads/candidate' -ExpectedObjectId $wrongObjectId
        } | Should -Throw -ExpectedMessage 'Branch changed after analysis; refusing to remove it: candidate'

        (Invoke-GitCommand -Repository $fixture.Repository -Arguments @('branch', '--list', 'candidate') | Out-String).Trim() | Should -Be 'candidate'
    }

    It 'keeps the branch and reports a preview when WhatIf is requested' {
        $fixture = New-BranchRemovalRepository

        $result = Remove-GitBranch -Repository $fixture.Repository -Name 'candidate' `
            -Ref 'refs/heads/candidate' -ExpectedObjectId $fixture.ObjectId -WhatIf

        $result.Status | Should -Be 'WhatIf'
        (Invoke-GitCommand -Repository $fixture.Repository -Arguments @('branch', '--list', 'candidate') | Out-String).Trim() |
                Should -Be 'candidate'
    }
}
