# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Invoke-GitCommand.ps1.

.DESCRIPTION
    Runs git against temporary repositories in TestDrive. The global and system
    configuration are redirected to TestDrive files for each test and restored afterwards.

.NOTES
    Dependencies: Pester 5 or later, Git for Windows. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Invoke-GitCommand.ps1')
    $script:Catalog = Join-Path $PSScriptRoot '..\..\..\git\l10n\de-DE\Messages.psd1'

    function New-TestRepository {
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $path | Out-Null
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { & git init --quiet $path | Out-Null } finally { $ErrorActionPreference = $previous }
        return $path
    }
}

Describe 'Invoke-GitCommand' {
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

    It 'returns the output of a command run without a repository' {
        $output = Invoke-GitCommand -Arguments @('--version')
        ($output -join ' ') | Should -Match '^git version'
    }

    It 'runs the command in the given repository' {
        $repository = New-TestRepository
        $output = Invoke-GitCommand -Repository $repository -Arguments @('rev-parse', '--is-inside-work-tree')
        ($output | Select-Object -First 1) | Should -Be 'true'
    }

    It 'throws an English error with the exit code when the command fails' {
        $repository = New-TestRepository
        { Invoke-GitCommand -Repository $repository -Arguments @('rev-parse', '--verify', 'no-such-ref') } |
            Should -Throw -ExpectedMessage 'Git command failed (exit code*'
    }

    It 'throws the German error text when the language is de' {
        $repository = New-TestRepository
        { Invoke-GitCommand -Repository $repository -Arguments @('rev-parse', '--verify', 'no-such-ref') -Language 'de' -MessagesPath $script:Catalog } |
            Should -Throw -ExpectedMessage 'Git-Befehl fehlgeschlagen*'
    }
}
