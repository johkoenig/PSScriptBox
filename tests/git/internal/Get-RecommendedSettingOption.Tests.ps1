# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Get-RecommendedSettingOption.ps1.

.DESCRIPTION
    Covers the prepended current value, the case-sensitive comparison, and localization.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-RecommendedSettingOption.ps1')
    $script:Options = @(
        [pscustomobject]@{ Value = 'true'; Text = 'Enables it' }
        [pscustomobject]@{ Value = 'false'; Text = 'Disables it' }
    )
    $script:Catalog = Join-Path $PSScriptRoot '..\..\..\git\l10n\de-DE\Messages.psd1'
}

Describe 'Get-RecommendedSettingOption' {
    It 'returns only the catalog options when no value is set' {
        $options = @(Get-RecommendedSettingOption -Options $script:Options -Current '')
        $options.Count | Should -Be 2
        $options[0].IsCurrent | Should -BeFalse
        $options[0].Value | Should -Be 'true'
    }

    It 'does not add the current value when it matches a catalog option' {
        $options = @(Get-RecommendedSettingOption -Options $script:Options -Current 'false')
        $options.Count | Should -Be 2
        $options.IsCurrent | Should -Not -Contain $true
    }

    It 'prepends a custom current value with the unchanged label' {
        $options = @(Get-RecommendedSettingOption -Options $script:Options -Current 'maybe')
        $options.Count | Should -Be 3
        $options[0].Value | Should -Be 'maybe'
        $options[0].Text | Should -Be 'Current value (unchanged)'
        $options[0].IsCurrent | Should -BeTrue
    }

    It 'compares the current value case-sensitively' {
        $options = @(Get-RecommendedSettingOption -Options $script:Options -Current 'True')
        $options.Count | Should -Be 3
        $options[0].Value | Should -Be 'True'
    }

    It 'localizes the option and current texts when the language is de' {
        $options = @(Get-RecommendedSettingOption -Options $script:Options -Current 'maybe' -Language 'de' -MessagesPath $script:Catalog)
        $options[0].Text | Should -Be 'Aktueller Wert (unverändert)'
        $options[1].Text | Should -Be 'Enables it'
        $options[2].Text | Should -Be 'Disables it'
    }
}
