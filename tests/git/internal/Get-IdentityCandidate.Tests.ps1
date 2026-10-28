# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Get-IdentityCandidate.ps1.

.DESCRIPTION
    Uses plain source entries, so no Git or directory access is needed.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Test-IdentityValue.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-IdentityCandidate.ps1')
    $script:Catalog = Join-Path $PSScriptRoot '..\..\..\git\l10n\de-DE\Messages.psd1'

    function New-Entry {
        param([object] $Value, [string] $Source, [object[]] $SourceArguments = @())
        [pscustomobject]@{ Value = $Value; Source = $Source; SourceArguments = $SourceArguments }
    }
}

Describe 'Get-IdentityCandidate' {
    It 'returns an empty array when there are no entries' {
        @(Get-IdentityCandidate -Key 'user.name').Count | Should -Be 0
    }

    It 'trims values and drops empty and null values' {
        $entries = @(
            New-Entry -Value ' Ann Lee ' -Source 'Windows display name'
            New-Entry -Value '   ' -Source 'Active Directory display name'
            New-Entry -Value $null -Source 'Existing Git setting ({0})' -SourceArguments @('Global')
        )
        $candidates = @(Get-IdentityCandidate -Key 'user.name' -Entries $entries)
        $candidates.Count | Should -Be 1
        $candidates[0].Value | Should -Be 'Ann Lee'
    }

    It 'keeps the first of case-insensitive duplicates' {
        $entries = @(
            New-Entry -Value 'ann@contoso.test' -Source 'Active Directory email'
            New-Entry -Value 'ANN@contoso.test' -Source 'Microsoft account'
        )
        $candidates = @(Get-IdentityCandidate -Key 'user.email' -Entries $entries)
        $candidates.Count | Should -Be 1
        $candidates[0].Value | Should -Be 'ann@contoso.test'
    }

    It 'drops email values that are not valid addresses' {
        $entries = @(New-Entry -Value 'not-an-email' -Source 'User principal name')
        @(Get-IdentityCandidate -Key 'user.email' -Entries $entries).Count | Should -Be 0
    }

    It 'keeps the order of the entries' {
        $entries = @(
            New-Entry -Value 'Bea' -Source 'Windows display name'
            New-Entry -Value 'Ann' -Source 'Windows display name'
        )
        $candidates = @(Get-IdentityCandidate -Key 'user.name' -Entries $entries)
        ($candidates | ForEach-Object { $_.Value }) -join ',' | Should -Be 'Bea,Ann'
    }

    It 'localizes the source label with the English text by default' {
        $entries = @(New-Entry -Value 'Ann' -Source 'Existing Git setting ({0})' -SourceArguments @('Local'))
        $candidates = @(Get-IdentityCandidate -Key 'user.name' -Entries $entries)
        $candidates[0].Source | Should -Be 'Existing Git setting (Local)'
    }

    It 'localizes the source label with the German text when the language is de' {
        $entries = @(
            New-Entry -Value 'Ann' -Source 'Existing Git setting ({0})' -SourceArguments @('Local')
            New-Entry -Value 'Bea' -Source 'Windows display name'
        )
        $candidates = @(Get-IdentityCandidate -Key 'user.name' -Entries $entries -Language 'de' -MessagesPath $script:Catalog)
        $candidates[0].Source | Should -Be 'Vorhandene Git-Einstellung (Local)'
        $candidates[1].Source | Should -Be 'Windows-Anzeigename'
    }
}
