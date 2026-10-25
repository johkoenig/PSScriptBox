# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Set-RecommendedGitSettings.ps1.

.DESCRIPTION
    Replaces the Git helpers with mocks, so the skip, preserve, and write
    decisions are tested without touching any Git configuration.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-GitConfigValue.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Set-GitConfigValue.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Set-RecommendedGitSettings.ps1')

    function New-Change {
        param([string] $Key, [object] $Value)
        [pscustomobject]@{ Key = $Key; Value = $Value }
    }
}

Describe 'Set-RecommendedGitSettings' {
    BeforeEach {
        Mock Get-GitConfigValue {
            param($Key)
            switch ($Key) {
                'init.defaultBranch' { return 'main' }
                'core.autocrlf' { return 'input' }
                default { return '' }
            }
        }
        Mock Set-GitConfigValue { }
    }

    It 'returns an empty array when there are no changes' {
        @(Set-RecommendedGitSettings -Scope 'Global').Count | Should -Be 0
        Should -Invoke Set-GitConfigValue -Times 0 -Exactly
    }

    It 'skips a null value without writing' {
        $result = @(Set-RecommendedGitSettings -Changes @(New-Change -Key 'fetch.prune' -Value $null) -Scope 'Global')
        $result[0].Status | Should -Be 'Skipped'
        $result[0].Key | Should -Be 'fetch.prune'
        Should -Invoke Set-GitConfigValue -Times 0 -Exactly
    }

    It 'preserves a value that equals the current setting without writing' {
        $result = @(Set-RecommendedGitSettings -Changes @(New-Change -Key 'init.defaultBranch' -Value 'main') -Scope 'Global')
        $result[0].Status | Should -Be 'Preserved'
        $result[0].Current | Should -Be 'main'
        Should -Invoke Set-GitConfigValue -Times 0 -Exactly
    }

    It 'treats a value that differs only in case as a change' {
        $result = @(Set-RecommendedGitSettings -Changes @(New-Change -Key 'core.autocrlf' -Value 'INPUT') -Scope 'Global')
        $result[0].Status | Should -Be 'Configured'
        Should -Invoke Set-GitConfigValue -Times 1 -Exactly
    }

    It 'writes a changed value and reports it as configured' {
        $result = @(Set-RecommendedGitSettings -Changes @(New-Change -Key 'fetch.prune' -Value 'true') -Scope 'Global')
        $result[0].Status | Should -Be 'Configured'
        $result[0].Value | Should -Be 'true'
        Should -Invoke Set-GitConfigValue -Times 1 -Exactly -ParameterFilter {
            $Key -eq 'fetch.prune' -and $Value -eq 'true' -and $Scope -eq 'Global'
        }
    }

    It 'passes the scope, repository, language, and catalog to the Git helpers' {
        $messages = @{ 'x' = 'y' }
        Set-RecommendedGitSettings -Changes @(New-Change -Key 'fetch.prune' -Value 'true') `
            -Scope 'Local' -Repository 'C:\repo' -Language 'de' -Messages $messages | Out-Null
        Should -Invoke Get-GitConfigValue -Times 1 -Exactly -ParameterFilter {
            $Scope -eq 'Local' -and $Repository -eq 'C:\repo' -and $Language -eq 'de'
        }
        Should -Invoke Set-GitConfigValue -Times 1 -Exactly -ParameterFilter {
            $Scope -eq 'Local' -and $Repository -eq 'C:\repo' -and $Language -eq 'de'
        }
    }
}
