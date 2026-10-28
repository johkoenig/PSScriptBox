# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Select-IdentityValue.ps1.

.DESCRIPTION
    Covers the candidate menu answers: default, numbers, custom entry, and invalid input.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Select-IdentityValue.ps1')
    $script:Candidates = @(
        [pscustomobject]@{ Value = 'Ann Lee'; Source = 'Existing Git setting (Local)' }
        [pscustomobject]@{ Value = 'Ann L.'; Source = 'Windows display name' }
    )
}

Describe 'Select-IdentityValue' {
    It 'selects the first candidate for an empty answer' {
        $choice = Select-IdentityValue -Candidates $script:Candidates -Answer ''
        $choice.Kind | Should -Be 'Candidate'
        $choice.Value | Should -Be 'Ann Lee'
    }

    It 'selects the candidate with the typed number' {
        $choice = Select-IdentityValue -Candidates $script:Candidates -Answer '2'
        $choice.Kind | Should -Be 'Candidate'
        $choice.Value | Should -Be 'Ann L.'
    }

    It 'ignores surrounding whitespace in the answer' {
        (Select-IdentityValue -Candidates $script:Candidates -Answer ' 2 ').Value | Should -Be 'Ann L.'
    }

    It 'selects the custom entry option after the last candidate' {
        $choice = Select-IdentityValue -Candidates $script:Candidates -Answer '3'
        $choice.Kind | Should -Be 'Custom'
        $choice.Value | Should -Be ''
    }

    It 'offers only the custom entry when there are no candidates' {
        (Select-IdentityValue -Candidates @() -Answer '1').Kind | Should -Be 'Custom'
    }

    It 'reports zero, numbers beyond the menu, and text as invalid' {
        (Select-IdentityValue -Candidates $script:Candidates -Answer '0').Kind | Should -Be 'Invalid'
        (Select-IdentityValue -Candidates $script:Candidates -Answer '4').Kind | Should -Be 'Invalid'
        (Select-IdentityValue -Candidates $script:Candidates -Answer 'abc').Kind | Should -Be 'Invalid'
    }
}
