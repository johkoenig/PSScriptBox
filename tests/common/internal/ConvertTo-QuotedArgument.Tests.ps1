# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for common\internal\ConvertTo-QuotedArgument.ps1.

.DESCRIPTION
    Checks quoting of plain values, embedded quotation marks, and trailing
    backslashes. Pure input and output, no mocks.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\ConvertTo-QuotedArgument.ps1')
}

Describe 'ConvertTo-QuotedArgument' {
    It 'wraps a plain value in quotes' {
        ConvertTo-QuotedArgument -Value 'C:\Temp\file.pdf' | Should -Be '"C:\Temp\file.pdf"'
    }

    It 'escapes embedded quotation marks' {
        ConvertTo-QuotedArgument -Value 'say "hi"' | Should -Be '"say \"hi\""'
    }

    It 'doubles a trailing backslash so the closing quote is not escaped' {
        ConvertTo-QuotedArgument -Value 'C:\Temp\' | Should -Be '"C:\Temp\\"'
    }
}
