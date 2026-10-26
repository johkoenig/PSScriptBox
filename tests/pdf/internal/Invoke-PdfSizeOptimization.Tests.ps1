# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Invoke-PdfSizeOptimization.ps1.

.DESCRIPTION
    Verifies failures before Ghostscript processing leave the input unchanged
    and remove temporary preflight files.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\ConvertTo-QuotedArgument.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Optimize-WithGhostscript.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Invoke-PdfSizeOptimization.ps1')
}

Describe 'Invoke-PdfSizeOptimization' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ('size-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Folder -Force | Out-Null
        $script:PdfPath = Join-Path $script:Folder 'document.pdf'
        [System.IO.File]::WriteAllBytes($script:PdfPath,[System.Text.Encoding]::ASCII.GetBytes('not a real pdf'))
        $script:Pdf = Get-Item -LiteralPath $script:PdfPath
    }

    It 'returns a failed result when the PDF protection check cannot run' {
        $result = Invoke-PdfSizeOptimization -Pdf $script:Pdf `
            -PythonPath 'C:\scriptbox-no-such\python.exe' `
            -GhostscriptPath 'C:\scriptbox-no-such\gs.exe' `
            -Dpi 200 -Quality 75 -MinFileSize 0 -ReplaceOriginal $false
        $result.Success | Should -BeFalse
        $result.Skipped | Should -BeFalse
        $result.FailureReason | Should -Not -BeNullOrEmpty
    }

    It 'does not modify the input when the protection check fails' {
        $before = [System.IO.File]::ReadAllBytes($script:PdfPath)
        Invoke-PdfSizeOptimization -Pdf $script:Pdf `
            -PythonPath 'C:\scriptbox-no-such\python.exe' `
            -GhostscriptPath 'C:\scriptbox-no-such\gs.exe' `
            -Dpi 200 -Quality 75 -MinFileSize 0 -ReplaceOriginal $false | Out-Null
        [System.IO.File]::ReadAllBytes($script:PdfPath) | Should -Be $before
    }

    It 'removes temporary files when the protection check fails' {
        Invoke-PdfSizeOptimization -Pdf $script:Pdf `
            -PythonPath 'C:\scriptbox-no-such\python.exe' `
            -GhostscriptPath 'C:\scriptbox-no-such\gs.exe' `
            -Dpi 200 -Quality 75 -MinFileSize 0 -ReplaceOriginal $false | Out-Null
        @(Get-ChildItem -LiteralPath $script:Folder -Force | Where-Object { $_.Name -ne 'document.pdf' }).Count | Should -Be 0
    }

    It 'skips files below the minimum size without invoking Python' {
        $result = Invoke-PdfSizeOptimization -Pdf $script:Pdf `
            -PythonPath 'C:\scriptbox-no-such\python.exe' `
            -GhostscriptPath 'C:\scriptbox-no-such\gs.exe' `
            -Dpi 300 -Quality 75 -MinFileSize 1MB -ReplaceOriginal $false
        $result.Success | Should -BeFalse
        $result.Skipped | Should -BeTrue
        $result.FailureReason | Should -Match '^Below minimum file size: 1[.,]00 MB$'
        [System.IO.File]::Exists((Join-Path $script:Folder '.check.py')) | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:Folder -Force | Where-Object { $_.Name -ne 'document.pdf' }).Count | Should -Be 0
    }
}
