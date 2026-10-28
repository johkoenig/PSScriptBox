# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Get-PdfInputFile.ps1.

.DESCRIPTION
    Builds a small folder tree under TestDrive with PDFs, an _orig backup, and a
    non-PDF file. No user folders are touched.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-PdfInputFile.ps1')

    $script:Root = Join-Path $TestDrive 'input'
    New-Item -ItemType Directory -Path (Join-Path $script:Root 'sub') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'a.pdf') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'a_orig.pdf') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'sub\b.pdf') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'note.txt') -Force | Out-Null
}

Describe 'Get-PdfInputFile' {
    It 'finds PDFs recursively in a folder, skipping _orig backups and other files' {
        $result = Get-PdfInputFile -Path $script:Root
        ($result.Files.Name | Sort-Object) | Should -Be @('a.pdf', 'b.pdf')
        $result.BasePath | Should -Be (Get-Item -LiteralPath $script:Root).FullName
    }

    It 'returns a single PDF file with its parent folder as base path' {
        $file = Join-Path $script:Root 'a.pdf'
        $result = Get-PdfInputFile -Path $file
        $result.Files.Count | Should -Be 1
        $result.Files[0].Name | Should -Be 'a.pdf'
        $result.BasePath | Should -Be (Get-Item -LiteralPath $script:Root).FullName
    }

    It 'trims quotation marks and whitespace from the path' {
        $result = Get-PdfInputFile -Path ('  "' + (Join-Path $script:Root 'a.pdf') + '"  ')
        $result.Files.Count | Should -Be 1
    }

    It 'throws when the path is blank' {
        { Get-PdfInputFile -Path '   ' } | Should -Throw 'No path was entered.'
    }

    It 'throws when the path does not exist' {
        { Get-PdfInputFile -Path (Join-Path $script:Root 'missing.pdf') } | Should -Throw 'Path not found*'
    }

    It 'throws when the file is not a PDF' {
        { Get-PdfInputFile -Path (Join-Path $script:Root 'note.txt') } |
            Should -Throw 'The selected file does not have a .pdf extension.'
    }
}
