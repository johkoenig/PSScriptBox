# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Get-GitConfigValue.ps1.

.DESCRIPTION
    Writes settings into temporary repositories and TestDrive configuration files.
    The user's real global and system configuration is never touched.

.NOTES
    Dependencies: Pester 5 or later, Git for Windows. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Invoke-GitCommand.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-GitConfigValue.ps1')
    $script:Catalog = @{ 'Could not read Git setting: {0}' = 'Git-Einstellung konnte nicht gelesen werden: {0}' }

    function New-TestRepository {
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $path | Out-Null
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { & git init --quiet $path | Out-Null } finally { $ErrorActionPreference = $previous }
        return $path
    }
}

Describe 'Get-GitConfigValue' {
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

    It 'returns an empty string for the Local scope without a repository path' {
        Get-GitConfigValue -Key 'user.name' -Scope 'Local' | Should -Be ''
    }

    It 'reads a value from the local repository configuration' {
        $repository = New-TestRepository
        & git -C $repository config --local user.name 'Ann Lee' | Out-Null
        Get-GitConfigValue -Key 'user.name' -Scope 'Local' -Repository $repository | Should -Be 'Ann Lee'
    }

    It 'reads a value from the global configuration' {
        & git config --global user.email 'ann@contoso.test' | Out-Null
        Get-GitConfigValue -Key 'user.email' -Scope 'Global' | Should -Be 'ann@contoso.test'
    }

    It 'returns an empty string when the key is not set' {
        $repository = New-TestRepository
        Get-GitConfigValue -Key 'user.name' -Scope 'Local' -Repository $repository | Should -Be ''
    }

    It 'returns an empty string for the System scope when the system file is missing' {
        Get-GitConfigValue -Key 'core.longpaths' -Scope 'System' | Should -Be ''
    }

    It 'throws an English error when the repository cannot be read' {
        $folder = Join-Path $TestDrive 'not-a-repository'
        New-Item -ItemType Directory -Path $folder | Out-Null
        { Get-GitConfigValue -Key 'user.name' -Scope 'Local' -Repository $folder } |
            Should -Throw -ExpectedMessage 'Could not read Git setting: user.name*'
    }

    It 'throws the German error text when the language is de' {
        $folder = Join-Path $TestDrive 'not-a-repository-de'
        New-Item -ItemType Directory -Path $folder | Out-Null
        { Get-GitConfigValue -Key 'user.name' -Scope 'Local' -Repository $folder -Language 'de' -Messages $script:Catalog } |
            Should -Throw -ExpectedMessage 'Git-Einstellung konnte nicht gelesen werden*'
    }
}
