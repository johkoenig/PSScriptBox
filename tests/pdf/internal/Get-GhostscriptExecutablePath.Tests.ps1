# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Get-GhostscriptExecutablePath.ps1.

.DESCRIPTION
    Mocks Get-ExecutablePath to check the lookup order without depending on
    what is installed on the machine.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-ExecutablePath.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-GhostscriptExecutablePath.ps1')
}

Describe 'Get-GhostscriptExecutablePath' {
    It 'prefers gswin64c over the other names' {
        Mock Get-ExecutablePath { "C:\gs\$Name.exe" }
        Get-GhostscriptExecutablePath | Should -Be 'C:\gs\gswin64c.exe'
        Should -Invoke Get-ExecutablePath -Times 1
    }

    It 'falls back to gswin32c and then gs' {
        Mock Get-ExecutablePath {
            if ($Name -eq 'gs') { return 'C:\gs\gs.exe' }
            return $null
        }
        Get-GhostscriptExecutablePath | Should -Be 'C:\gs\gs.exe'
        Should -Invoke Get-ExecutablePath -Times 3
    }

    It 'returns $null when no Ghostscript name is found' {
        Mock Get-ExecutablePath { $null }
        Get-GhostscriptExecutablePath | Should -BeNullOrEmpty
    }
}
