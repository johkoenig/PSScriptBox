# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Get-LanguageDownloadHint.ps1.

.DESCRIPTION
    Checks the three notice lines for the English catalog. Nothing is printed.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-LanguageDownloadHint.ps1')
}

Describe 'Get-LanguageDownloadHint' {
    It 'returns three lines with the missing languages, the URL, and the tessdata path' {
        $lines = Get-LanguageDownloadHint -MissingLanguages @('deu', 'eng') -TessdataPath 'C:\Tess\tessdata' `
            -TessdataUrl 'https://example.test/tessdata'
        $lines.Count | Should -Be 3
        $lines[0] | Should -Be 'Missing required language data: deu, eng.'
        $lines[1] | Should -Match 'https://example\.test/tessdata'
        $lines[2] | Should -Match 'C:\\Tess\\tessdata'
    }

    It 'lists a single missing language without a separator' {
        $lines = Get-LanguageDownloadHint -MissingLanguages @('deu') -TessdataPath 'C:\Tess\tessdata' `
            -TessdataUrl 'https://example.test/tessdata'
        $lines[0] | Should -Be 'Missing required language data: deu.'
    }
}
