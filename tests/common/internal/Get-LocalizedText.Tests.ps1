# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for common\internal\Get-LocalizedText.ps1.

.DESCRIPTION
    Verifies explicit and culture-derived language selection using the
    repository's German message catalog.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    $script:MessagesPath = Join-Path $PSScriptRoot '..\..\..\git\l10n\de-DE\Messages.psd1'
}

Describe 'Get-LocalizedText' {
    It 'returns the English template when the language is en' {
        Get-LocalizedText -Text 'Git command failed (exit code {0}): {1}' -Arguments @(2, 'detail') -Language 'en' -MessagesPath $script:MessagesPath | Should -Be 'Git command failed (exit code 2): detail'
    }

    It 'returns the German text when the language is de' {
        Get-LocalizedText -Text 'Git command failed (exit code {0}): {1}' -Arguments @(2, 'detail') -Language 'de' -MessagesPath $script:MessagesPath | Should -Be 'Git-Befehl fehlgeschlagen (Exitcode 2): detail'
    }

    It 'falls back to English when no German entry exists' {
        Get-LocalizedText -Text 'Unknown message' -Language 'de' -MessagesPath $script:MessagesPath | Should -Be 'Unknown message'
    }

    It 'returns the template unchanged when no arguments are given' {
        Get-LocalizedText -Text 'Plain {0}' -Language 'en' -MessagesPath $script:MessagesPath | Should -Be 'Plain {0}'
    }

    It 'uses the current UI culture when the language is omitted' {
        $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture
        try
        {
            [System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::new('de-DE')
            Get-LocalizedText -Text 'Git command failed (exit code {0}): {1}' -Arguments @(2, 'detail') -MessagesPath $script:MessagesPath | Should -Be 'Git-Befehl fehlgeschlagen (Exitcode 2): detail'
        }
        finally
        {
            [System.Threading.Thread]::CurrentThread.CurrentUICulture = $originalCulture
        }
    }

    It 'requires a catalog path for German output' {
        { Get-LocalizedText -Text 'Hello' -Language 'de' } | Should -Throw '*MessagesPath is required*'
    }
}
