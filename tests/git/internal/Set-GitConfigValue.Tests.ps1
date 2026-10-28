# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Set-GitConfigValue.ps1.

.DESCRIPTION
    Writes into temporary repositories and TestDrive configuration files only.
    The user's real global configuration is redirected per test.

.NOTES
    Dependencies: Pester 5 or later, Git for Windows. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Invoke-GitCommand.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Set-GitConfigValue.ps1')

    function New-TestRepository {
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $path | Out-Null
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { & git init --quiet $path | Out-Null } finally { $ErrorActionPreference = $previous }
        return $path
    }
}

Describe 'Set-GitConfigValue' {
    BeforeEach {
        $script:PreviousGlobal = $env:GIT_CONFIG_GLOBAL
        $script:PreviousSystem = $env:GIT_CONFIG_SYSTEM
        $env:GIT_CONFIG_GLOBAL = Join-Path $TestDrive 'global.gitconfig'
        $env:GIT_CONFIG_SYSTEM = Join-Path $TestDrive 'system.gitconfig'
    }

    AfterEach {
        $env:GIT_CONFIG_GLOBAL = $script:PreviousGlobal
        $env:GIT_CONFIG_SYSTEM = $script:PreviousSystem
    }

    It 'writes a value to the local repository configuration' {
        $repository = New-TestRepository
        Set-GitConfigValue -Key 'user.name' -Value 'Ann Lee' -Scope 'Local' -Repository $repository
        (& git -C $repository config --local --get user.name) | Should -Be 'Ann Lee'
    }

    It 'overwrites an existing local value' {
        $repository = New-TestRepository
        Set-GitConfigValue -Key 'user.name' -Value 'Old' -Scope 'Local' -Repository $repository
        Set-GitConfigValue -Key 'user.name' -Value 'New' -Scope 'Local' -Repository $repository
        (& git -C $repository config --local --get user.name) | Should -Be 'New'
    }

    It 'writes a value to the global configuration without a repository' {
        Set-GitConfigValue -Key 'user.email' -Value 'ann@contoso.test' -Scope 'Global'
        (& git config --global --get user.email) | Should -Be 'ann@contoso.test'
    }

    It 'does not write a value when WhatIf is requested' {
        $repository = New-TestRepository
        $result = Set-GitConfigValue -Key 'user.name' -Value 'Ann Lee' `
            -Scope 'Local' -Repository $repository -WhatIf

        $result | Should -BeFalse
        (& git -C $repository config --local --get user.name 2> $null) | Should -BeNullOrEmpty
    }

    It 'throws when a local value is written outside a repository' {
        $folder = Join-Path $TestDrive 'not-a-repository'
        New-Item -ItemType Directory -Path $folder | Out-Null
        { Set-GitConfigValue -Key 'user.name' -Value 'Ann' -Scope 'Local' -Repository $folder } |
            Should -Throw -ExpectedMessage 'Git command failed*'
    }

    It 'rejects an empty value' {
        { Set-GitConfigValue -Key 'user.name' -Value '' -Scope 'Global' } | Should -Throw
    }
}
