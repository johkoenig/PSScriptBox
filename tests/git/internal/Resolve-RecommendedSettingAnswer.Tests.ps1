# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Resolve-RecommendedSettingAnswer.ps1.

.DESCRIPTION
    Covers skip, default, option matching, custom values, and invalid answers.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Resolve-RecommendedSettingAnswer.ps1')
    $script:Options = @(
        [pscustomobject]@{ Value = 'main' }
        [pscustomobject]@{ Value = 'master' }
    )
}

Describe 'Resolve-RecommendedSettingAnswer' {
    It 'skips the setting for a dash' {
        $choice = Resolve-RecommendedSettingAnswer -Answer '-' -Default 'main' -Options $script:Options
        $choice.Kind | Should -Be 'Skip'
        $choice.Value | Should -BeNullOrEmpty
    }

    It 'returns the default for an empty answer' {
        $choice = Resolve-RecommendedSettingAnswer -Answer '  ' -Default 'main' -Options $script:Options
        $choice.Kind | Should -Be 'Value'
        $choice.Value | Should -Be 'main'
    }

    It 'matches an option case-insensitively and returns its canonical value' {
        $choice = Resolve-RecommendedSettingAnswer -Answer 'MASTER' -Default 'main' -Options $script:Options
        $choice.Kind | Should -Be 'Value'
        $choice.Value | Should -Be 'master'
    }

    It 'accepts any text when custom values are allowed' {
        $choice = Resolve-RecommendedSettingAnswer -Answer 'develop' -Default 'main' -Options $script:Options -AllowCustom
        $choice.Kind | Should -Be 'Value'
        $choice.Value | Should -Be 'develop'
    }

    It 'reports text that matches no option as invalid when custom values are not allowed' {
        $choice = Resolve-RecommendedSettingAnswer -Answer 'develop' -Default 'main' -Options $script:Options
        $choice.Kind | Should -Be 'Invalid'
        $choice.Value | Should -BeNullOrEmpty
    }
}
