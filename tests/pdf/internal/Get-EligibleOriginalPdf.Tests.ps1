# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Get-EligibleOriginalPdf.ps1.

.DESCRIPTION
    Creates fixture folders under TestDrive only. Each test uses its own
    subfolder so that the recursive searches do not interfere with each other.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-EligibleOriginalPdf.ps1')

    function script:New-Fixture {
        param([Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $RelativePaths)
        $root = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        foreach ($relativePath in $RelativePaths) {
            $fullPath = Join-Path $root $relativePath
            $parent = Split-Path -Parent $fullPath
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            New-Item -ItemType File -Path $fullPath -Force | Out-Null
        }
        return $root
    }
}

Describe 'Get-EligibleOriginalPdf' {
    It 'returns an _orig PDF when the processed PDF exists in the same folder' {
        $root = New-Fixture -Name 'basic' -RelativePaths @('scan.pdf', 'scan_orig.pdf')

        $eligible = @(Get-EligibleOriginalPdf -RootPath $root)
        $eligible.Count | Should -Be 1
        $eligible[0].Name | Should -Be 'scan_orig.pdf'
        $eligible[0] | Should -BeOfType ([System.IO.FileInfo])
    }

    It 'skips an _orig PDF whose processed PDF is missing' {
        $root = New-Fixture -Name 'missing-processed' -RelativePaths @('lonely_orig.pdf')

        @(Get-EligibleOriginalPdf -RootPath $root).Count | Should -Be 0
    }

    It 'searches subfolders recursively and keeps the processed PDF in the same folder' {
        $root = New-Fixture -Name 'nested' -RelativePaths @('sub\deep\invoice.pdf', 'sub\deep\invoice_orig.pdf', 'other\invoice_orig.pdf')

        $eligible = @(Get-EligibleOriginalPdf -RootPath $root)
        $eligible.Count | Should -Be 1
        $eligible[0].FullName | Should -Be (Join-Path $root 'sub\deep\invoice_orig.pdf')
    }

    It 'matches the _orig suffix and the .pdf extension case-insensitively' {
        $root = New-Fixture -Name 'case' -RelativePaths @('Report.PDF', 'REPORT_ORIG.pdf')

        @(Get-EligibleOriginalPdf -RootPath $root).Count | Should -Be 1
    }

    It 'ignores files whose extension is not .pdf' {
        $root = New-Fixture -Name 'extension' -RelativePaths @('notes.txt', 'notes_orig.txt', 'image_orig.png', 'image.png')

        @(Get-EligibleOriginalPdf -RootPath $root).Count | Should -Be 0
    }

    It 'ignores PDFs whose base name does not end with _orig' {
        $root = New-Fixture -Name 'no-suffix' -RelativePaths @('plain.pdf', 'plain_original.pdf', 'plain.pdf.bak')

        @(Get-EligibleOriginalPdf -RootPath $root).Count | Should -Be 0
    }

    It 'ignores a folder named like an _orig PDF' {
        $root = New-Fixture -Name 'folder-name' -RelativePaths @('dir.pdf\placeholder.txt')
        New-Item -ItemType Directory -Path (Join-Path $root 'dir_orig.pdf') | Out-Null

        @(Get-EligibleOriginalPdf -RootPath $root).Count | Should -Be 0
    }

    It 'ignores a processed path that is a folder instead of a file' {
        $root = New-Fixture -Name 'processed-folder' -RelativePaths @('folder_orig.pdf')
        New-Item -ItemType Directory -Path (Join-Path $root 'folder.pdf') | Out-Null

        @(Get-EligibleOriginalPdf -RootPath $root).Count | Should -Be 0
    }

    It 'includes hidden original backups' {
        $root = New-Fixture -Name 'hidden' -RelativePaths @('hidden.pdf', 'hidden_orig.pdf')
        (Get-Item -LiteralPath (Join-Path $root 'hidden_orig.pdf')).Attributes = 'Hidden'

        @(Get-EligibleOriginalPdf -RootPath $root).Count | Should -Be 1
    }

    It 'returns nothing for an empty folder' {
        $root = New-Fixture -Name 'empty' -RelativePaths @()

        @(Get-EligibleOriginalPdf -RootPath $root).Count | Should -Be 0
    }
}
