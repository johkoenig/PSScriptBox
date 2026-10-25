# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Get-PdfToolLocation.ps1.

.DESCRIPTION
    Mocks every lookup helper, so the real PATH, registry, Chocolatey folders,
    and Python installations are never read.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-ExecutablePath.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-GhostscriptExecutablePath.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-PdfPythonRuntime.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-PdfToolLocation.ps1')
}

Describe 'Get-PdfToolLocation' {
    BeforeEach {
        Mock Get-ExecutablePath {
            switch ($Name) {
                'choco' { 'C:\fake\choco.exe' }
                'tesseract' { 'C:\fake\tesseract.exe' }
                default { $null }
            }
        }
        Mock Get-GhostscriptExecutablePath { 'C:\fake\gswin64c.exe' }
        Mock Get-PdfPythonRuntime {
            [pscustomobject]@{ Path = 'C:\fake\python.exe'; Scope = 'User'; Discovery = 'test' }
        }
    }

    It 'returns the located paths and the Python scope' {
        $location = Get-PdfToolLocation
        $location.ChocolateyPath | Should -Be 'C:\fake\choco.exe'
        $location.PythonPath | Should -Be 'C:\fake\python.exe'
        $location.PythonScope | Should -Be 'User'
        $location.TesseractPath | Should -Be 'C:\fake\tesseract.exe'
        $location.GhostscriptPath | Should -Be 'C:\fake\gswin64c.exe'
    }

    It 'passes the preferred Python path to the runtime lookup' {
        Get-PdfToolLocation -PreferredPythonPath 'C:\fake\preferred.exe' | Out-Null
        Should -Invoke Get-PdfPythonRuntime -Times 1 -Exactly -ParameterFilter { $PreferredPath -eq 'C:\fake\preferred.exe' }
    }

    It 'returns null Python fields when no interpreter is found' {
        Mock Get-PdfPythonRuntime { $null }
        $location = Get-PdfToolLocation
        $location.PythonPath | Should -BeNullOrEmpty
        $location.PythonScope | Should -BeNullOrEmpty
    }

    It 'returns null for every tool that is not found' {
        Mock Get-ExecutablePath { $null }
        Mock Get-GhostscriptExecutablePath { $null }
        Mock Get-PdfPythonRuntime { $null }
        $location = Get-PdfToolLocation
        $location.ChocolateyPath | Should -BeNullOrEmpty
        $location.TesseractPath | Should -BeNullOrEmpty
        $location.GhostscriptPath | Should -BeNullOrEmpty
    }
}
