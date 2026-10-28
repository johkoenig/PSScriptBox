# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for common\internal\Get-FileSha256.ps1.

.DESCRIPTION
    Hashes files under TestDrive, compares the result with the published SHA-256
    test vector for "abc", and checks the output format and error behavior.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-FileSha256.ps1')
}

Describe 'Get-FileSha256' {
    It 'returns the uppercase hexadecimal SHA-256 hash of the file content' {
        $path = Join-Path $TestDrive 'abc.bin'
        [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::ASCII.GetBytes('abc'))
        Get-FileSha256 -Path $path | Should -Be 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD'
    }

    It 'matches Get-FileHash for binary content' {
        $path = Join-Path $TestDrive 'sample.bin'
        [System.IO.File]::WriteAllBytes($path, [byte[]](0..255))
        Get-FileSha256 -Path $path | Should -Be (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }

    It 'returns an uppercase 64-character hexadecimal string' {
        $path = Join-Path $TestDrive 'format.txt'
        [System.IO.File]::WriteAllText($path, 'format')
        Get-FileSha256 -Path $path | Should -Match '^[0-9A-F]{64}$'
    }

    It 'returns different hashes for different content' {
        $first = Join-Path $TestDrive 'first.bin'
        $second = Join-Path $TestDrive 'second.bin'
        [System.IO.File]::WriteAllBytes($first, [byte[]](1, 2, 3))
        [System.IO.File]::WriteAllBytes($second, [byte[]](1, 2, 4))
        Get-FileSha256 -Path $first | Should -Not -Be (Get-FileSha256 -Path $second)
    }

    It 'throws when the file does not exist' {
        { Get-FileSha256 -Path (Join-Path $TestDrive 'missing.bin') } | Should -Throw
    }
}
