# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Test-IdentityValue.ps1.

.DESCRIPTION
    Covers the name and email validation rules without external dependencies.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Test-IdentityValue.ps1')
}

Describe 'Test-IdentityValue' {
    It 'accepts a non-empty name' {
        Test-IdentityValue -Key 'user.name' -Value 'Ann Lee' | Should -BeTrue
    }

    It 'rejects an empty or whitespace name' {
        Test-IdentityValue -Key 'user.name' -Value '' | Should -BeFalse
        Test-IdentityValue -Key 'user.name' -Value '   ' | Should -BeFalse
    }

    It 'rejects a null name' {
        Test-IdentityValue -Key 'user.name' -Value $null | Should -BeFalse
    }

    It 'accepts a plain email address' {
        Test-IdentityValue -Key 'user.email' -Value 'ann@contoso.test' | Should -BeTrue
    }

    It 'accepts an email address with surrounding whitespace' {
        Test-IdentityValue -Key 'user.email' -Value '  ann@contoso.test  ' | Should -BeTrue
    }

    It 'rejects an email address without a domain dot' {
        Test-IdentityValue -Key 'user.email' -Value 'ann@contoso' | Should -BeFalse
    }

    It 'rejects an email address with spaces or a second @' {
        Test-IdentityValue -Key 'user.email' -Value 'ann lee@contoso.test' | Should -BeFalse
        Test-IdentityValue -Key 'user.email' -Value 'ann@x@contoso.test' | Should -BeFalse
    }

    It 'rejects an empty email address' {
        Test-IdentityValue -Key 'user.email' -Value '' | Should -BeFalse
    }
}
