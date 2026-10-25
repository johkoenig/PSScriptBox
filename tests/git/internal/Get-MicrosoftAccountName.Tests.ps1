# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Get-MicrosoftAccountName.ps1.

.DESCRIPTION
    Replaces the registry access with mocks so that the test never reads the
    signed-in user's real IdentityCRL keys.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-MicrosoftAccountName.ps1')
}

Describe 'Get-MicrosoftAccountName' {
    It 'returns an empty array when the registry key is missing' {
        Mock Test-Path { return $false }
        @(Get-MicrosoftAccountName).Count | Should -Be 0
    }

    It 'returns the child key names of the account key' {
        Mock Test-Path { return $true }
        Mock Get-ChildItem {
            [pscustomobject]@{ PSChildName = 'ann@contoso.test' }
            [pscustomobject]@{ PSChildName = 'ann@fabrikam.test' }
        }
        $names = @(Get-MicrosoftAccountName)
        $names.Count | Should -Be 2
        $names | Should -Contain 'ann@contoso.test'
        $names | Should -Contain 'ann@fabrikam.test'
    }

    It 'returns an empty array when the registry cannot be read' {
        Mock Test-Path { return $true }
        Mock Get-ChildItem { throw 'Access denied' }
        @(Get-MicrosoftAccountName).Count | Should -Be 0
    }
}
