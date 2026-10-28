# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Invoke-OriginalPdfRestore.ps1.

.DESCRIPTION
    Exercises restoration using temporary files under Pester's TestDrive.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Invoke-OriginalPdfRestore.ps1')
}

Describe 'Invoke-OriginalPdfRestore' {
    It 'replaces the processed PDF with the original and removes the backup' {
        $folder = Join-Path $TestDrive 'restore-success'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $processedPath = Join-Path $folder 'document.pdf'
        $originalPath = Join-Path $folder 'document_orig.pdf'
        [System.IO.File]::WriteAllText($processedPath, 'processed content')
        [System.IO.File]::WriteAllText($originalPath, 'original content')

        $result = Invoke-OriginalPdfRestore -OriginalFile (Get-Item -LiteralPath $originalPath)

        $result.Success | Should -BeTrue
        $result.ProcessedPath | Should -Be $processedPath
        [System.IO.File]::ReadAllText($processedPath) | Should -Be 'original content'
        Test-Path -LiteralPath $originalPath | Should -BeFalse
    }

    It 'reports a failure and preserves the original when the processed PDF is missing' {
        $folder = Join-Path $TestDrive 'restore-missing-target'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $originalPath = Join-Path $folder 'document_orig.pdf'
        [System.IO.File]::WriteAllText($originalPath, 'original content')

        $result = Invoke-OriginalPdfRestore -OriginalFile (Get-Item -LiteralPath $originalPath)

        $result.Success | Should -BeFalse
        $result.Error | Should -Not -BeNullOrEmpty
        [System.IO.File]::ReadAllText($originalPath) | Should -Be 'original content'
    }
}
