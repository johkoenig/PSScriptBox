# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Get-AccountNameFormat.ps1.

.DESCRIPTION
    Calls the Windows GetUserNameEx API for the signed-in account. The tests only
    check the result type and the failure path, because the value depends on the
    account type of the test machine.

.NOTES
    Dependencies: Pester 5 or later, Windows. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-AccountNameFormat.ps1')
}

Describe 'Get-AccountNameFormat' {
    It 'returns a string for the display name format' {
        Get-AccountNameFormat -Format 3 | Should -BeOfType ([string])
    }

    It 'returns a string for the user principal name format' {
        Get-AccountNameFormat -Format 8 | Should -BeOfType ([string])
    }

    It 'returns an empty string for an unknown format' {
        Get-AccountNameFormat -Format 9999 | Should -BeNullOrEmpty
    }
}
