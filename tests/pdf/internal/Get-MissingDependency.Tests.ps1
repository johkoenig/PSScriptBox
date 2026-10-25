# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Get-MissingDependency.ps1.

.DESCRIPTION
    Passes resolved locations as parameters and mocks Test-PythonModule, so no
    Python installation is needed.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Test-PythonModule.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-MissingDependency.ps1')

    $script:Runtime = [pscustomobject]@{ Path = 'C:\Python\python.exe'; Scope = 'User' }
}

Describe 'Get-MissingDependency' {
    It 'reports nothing missing when everything is present' {
        Mock Test-PythonModule { $true }
        $result = Get-MissingDependency -PythonRuntime $script:Runtime -TesseractPath 'C:\Tesseract\tesseract.exe' -GhostscriptPath 'C:\gs\gswin64c.exe'
        $result.Missing.Count | Should -Be 0
        $result.OptionalMissing.Count | Should -Be 0
        $result.PythonPath | Should -Be 'C:\Python\python.exe'
        $result.PythonScope | Should -Be 'User'
        $result.GhostscriptPath | Should -Be 'C:\gs\gswin64c.exe'
    }

    It 'reports the Python interpreter and Tesseract as missing without a runtime' {
        Mock Test-PythonModule { $true }
        $result = Get-MissingDependency -PythonRuntime $null -TesseractPath $null -GhostscriptPath $null
        $result.Missing | Should -Be @('Python interpreter', 'Tesseract')
        $result.PythonPath | Should -BeNullOrEmpty
        $result.PythonScope | Should -BeNullOrEmpty
        Should -Invoke Test-PythonModule -Times 0
    }

    It 'reports a missing Python module by its catalog text' {
        Mock Test-PythonModule { $ModuleName -ne 'pikepdf' }
        $result = Get-MissingDependency -PythonRuntime $script:Runtime -TesseractPath 'C:\Tesseract\tesseract.exe' -GhostscriptPath 'C:\gs\gs.exe'
        $result.Missing | Should -Be @('pikepdf (Python module)')
    }

    It 'reports both Python modules when both are missing, in the original order' {
        Mock Test-PythonModule { $false }
        $result = Get-MissingDependency -PythonRuntime $script:Runtime -TesseractPath 'C:\Tesseract\tesseract.exe' -GhostscriptPath 'C:\gs\gs.exe'
        $result.Missing | Should -Be @('OCRmyPDF (Python module)', 'pikepdf (Python module)')
    }

    It 'reports Ghostscript as optional when it is missing' {
        Mock Test-PythonModule { $true }
        $result = Get-MissingDependency -PythonRuntime $script:Runtime -TesseractPath 'C:\Tesseract\tesseract.exe' -GhostscriptPath $null
        $result.Missing.Count | Should -Be 0
        $result.OptionalMissing | Should -Be @('Ghostscript (required only with -GhostscriptDpi)')
        $result.GhostscriptPath | Should -BeNullOrEmpty
    }

    It 'ignores Ghostscript entirely with -NoGhostscript' {
        Mock Test-PythonModule { $true }
        $result = Get-MissingDependency -PythonRuntime $script:Runtime -TesseractPath 'C:\Tesseract\tesseract.exe' -GhostscriptPath 'C:\gs\gs.exe' -NoGhostscript $true
        $result.OptionalMissing.Count | Should -Be 0
        $result.GhostscriptPath | Should -BeNullOrEmpty
    }
}
