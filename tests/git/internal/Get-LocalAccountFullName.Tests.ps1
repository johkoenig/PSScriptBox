# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Get-LocalAccountFullName.ps1.

.DESCRIPTION
    Reads local account data through ADSI. Only read access is used; the tests
    check the fallback for a missing account and the result type for the current account.

.NOTES
    Dependencies: Pester 5 or later, Windows. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-LocalAccountFullName.ps1')
}

Describe 'Get-LocalAccountFullName' {
    It 'returns an empty string when the account does not exist' {
        Get-LocalAccountFullName -UserName 'PSScriptBox-no-such-account' -MachineName ([Environment]::MachineName) |
            Should -Be ''
    }

    It 'returns a string for the current account' {
        Get-LocalAccountFullName -UserName ([Environment]::UserName) -MachineName ([Environment]::MachineName) |
            Should -BeOfType ([string])
    }
}
