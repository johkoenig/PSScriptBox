# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for common\internal\Get-LocalizedText.ps1.

.DESCRIPTION
    Passes language and message catalog explicitly, so most tests need no
    script-scope state.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    $script:Catalog = @{ 'Hello {0}' = 'Hallo {0}' }
}

Describe 'Get-LocalizedText' {
    It 'returns the English template when the language is en' {
        Get-LocalizedText -Text 'Hello {0}' -Arguments @('Ann') -Language 'en' -Messages $script:Catalog | Should -Be 'Hello Ann'
    }

    It 'returns the German text when the language is de' {
        Get-LocalizedText -Text 'Hello {0}' -Arguments @('Ann') -Language 'de' -Messages $script:Catalog | Should -Be 'Hallo Ann'
    }

    It 'falls back to English when no German entry exists' {
        Get-LocalizedText -Text 'Unknown message' -Language 'de' -Messages @{} | Should -Be 'Unknown message'
    }

    It 'returns the template unchanged when no arguments are given' {
        Get-LocalizedText -Text 'Plain {0}' -Language 'en' -Messages @{} | Should -Be 'Plain {0}'
    }

    It 'uses the script language and catalog when no parameters are passed' {
        $script:OutputLanguage = 'de'
        $script:GermanMessages = $script:Catalog
        Get-LocalizedText -Text 'Hello {0}' -Arguments @('Ann') | Should -Be 'Hallo Ann'
    }
}
