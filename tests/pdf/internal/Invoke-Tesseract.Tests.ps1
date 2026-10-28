# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Invoke-Tesseract.ps1.

.DESCRIPTION
    Uses cmd.exe as a generic executable that prints to both streams and returns
    a chosen exit code. Tesseract itself is not required.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Invoke-Tesseract.ps1')

    $script:Cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
}

Describe 'Invoke-Tesseract' {
    It 'returns the exit code and both output streams' {
        $result = Invoke-Tesseract -TesseractPath $script:Cmd -Arguments '/c "echo out-text & echo err-text 1>&2 & exit 3"'
        $result.ExitCode | Should -Be 3
        $result.StdOut | Should -Match 'out-text'
        $result.StdErr | Should -Match 'err-text'
    }

    It 'returns exit code 0 for a successful run' {
        $result = Invoke-Tesseract -TesseractPath $script:Cmd -Arguments '/c "exit 0"'
        $result.ExitCode | Should -Be 0
    }

    It 'throws when the executable does not exist' {
        { Invoke-Tesseract -TesseractPath 'C:\PSScriptBox-no-such\tesseract.exe' -Arguments '--version' } | Should -Throw
    }
}
