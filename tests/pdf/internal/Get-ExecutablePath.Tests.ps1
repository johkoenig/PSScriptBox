# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Get-ExecutablePath.ps1.

.DESCRIPTION
    Uses the real command lookup with a command that always exists on Windows
    and a name that never exists. No mocks.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-ExecutablePath.ps1')
}

Describe 'Get-ExecutablePath' {
    It 'returns $null for an unknown command' {
        Get-ExecutablePath -Name 'scriptbox-no-such-command-xyz' | Should -BeNullOrEmpty
    }

    It 'returns a full path for an existing command' {
        $path = Get-ExecutablePath -Name 'cmd'
        $path | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
    }
}
