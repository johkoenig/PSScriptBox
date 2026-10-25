# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Get-PdfSetupState.ps1.

.DESCRIPTION
    Mocks Invoke-SetupProcess and Get-TesseractTrainingStatus, so no executable
    is started. Tool paths are fake values under C:\fake.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Invoke-SetupProcess.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-TesseractTrainingStatus.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-PdfSetupState.ps1')

    $script:FullLocation = [pscustomobject]@{
        ChocolateyPath  = 'C:\fake\choco.exe'
        PythonPath      = 'C:\fake\python.exe'
        PythonScope     = 'User'
        TesseractPath   = 'C:\fake\tesseract.exe'
        GhostscriptPath = 'C:\fake\gswin64c.exe'
    }
}

Describe 'Get-PdfSetupState' {
    BeforeEach {
        Mock Invoke-SetupProcess {
            [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }
        Mock Get-TesseractTrainingStatus {
            [pscustomobject]@{ Languages = @('eng'); TessdataPath = 'C:\fake\tessdata'; CheckSucceeded = $true }
        }
    }

    It 'reports nothing as available and runs no checks when no tool was located' {
        $emptyLocation = [pscustomobject]@{
            ChocolateyPath = $null; PythonPath = $null; PythonScope = $null
            TesseractPath = $null; GhostscriptPath = $null
        }
        $state = Get-PdfSetupState -ToolLocation $emptyLocation
        $state.ChocolateyAvailable | Should -BeFalse
        $state.PythonAvailable | Should -BeFalse
        $state.OcrMyPdfAvailable | Should -BeFalse
        $state.PikePdfAvailable | Should -BeFalse
        $state.TesseractAvailable | Should -BeFalse
        $state.GhostscriptAvailable | Should -BeFalse
        $state.TrainingStatus | Should -BeNullOrEmpty
        Should -Invoke Invoke-SetupProcess -Times 0 -Exactly
    }

    It 'reports every tool as available when all checks pass' {
        $state = Get-PdfSetupState -ToolLocation $script:FullLocation
        $state.ChocolateyAvailable | Should -BeTrue
        $state.PythonAvailable | Should -BeTrue
        $state.OcrMyPdfAvailable | Should -BeTrue
        $state.PikePdfAvailable | Should -BeTrue
        $state.TesseractAvailable | Should -BeTrue
        $state.GhostscriptAvailable | Should -BeTrue
        $state.PythonScope | Should -Be 'User'
        $state.TrainingStatus.CheckSucceeded | Should -BeTrue
        Should -Invoke Invoke-SetupProcess -Times 6 -Exactly
        Should -Invoke Get-TesseractTrainingStatus -Times 1 -Exactly
    }

    It 'checks Ghostscript with -version and the other tools with --version' {
        Get-PdfSetupState -ToolLocation $script:FullLocation | Out-Null
        Should -Invoke Invoke-SetupProcess -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'C:\fake\gswin64c.exe' -and $Arguments -contains '-version'
        }
        Should -Invoke Invoke-SetupProcess -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'C:\fake\tesseract.exe' -and $Arguments -contains '--version'
        }
    }

    It 'skips the package checks when Python fails its version check' {
        Mock Invoke-SetupProcess {
            [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = '' }
        } -ParameterFilter { $FilePath -eq 'C:\fake\python.exe' }
        $state = Get-PdfSetupState -ToolLocation $script:FullLocation
        $state.PythonAvailable | Should -BeFalse
        $state.OcrMyPdfAvailable | Should -BeFalse
        Should -Invoke Invoke-SetupProcess -Times 0 -Exactly -ParameterFilter { $Arguments -contains 'import ocrmypdf' }
        Should -Invoke Invoke-SetupProcess -Times 0 -Exactly -ParameterFilter { $Arguments -contains 'import pikepdf' }
    }

    It 'marks only the package whose import fails as missing' {
        Mock Invoke-SetupProcess {
            [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = '' }
        } -ParameterFilter { $Arguments -contains 'import pikepdf' }
        $state = Get-PdfSetupState -ToolLocation $script:FullLocation
        $state.OcrMyPdfAvailable | Should -BeTrue
        $state.PikePdfAvailable | Should -BeFalse
    }

    It 'skips training inspection when Tesseract fails its version check' {
        Mock Invoke-SetupProcess {
            [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = '' }
        } -ParameterFilter { $FilePath -eq 'C:\fake\tesseract.exe' }
        $state = Get-PdfSetupState -ToolLocation $script:FullLocation
        $state.TesseractAvailable | Should -BeFalse
        $state.TrainingStatus | Should -BeNullOrEmpty
        Should -Invoke Get-TesseractTrainingStatus -Times 0 -Exactly
    }

    It 'passes the UI language and messages to the process runner' {
        Get-PdfSetupState -ToolLocation $script:FullLocation -UiLanguage 'de' -Messages @{} | Out-Null
        Should -Invoke Invoke-SetupProcess -Times 6 -Exactly -ParameterFilter { $UiLanguage -eq 'de' }
    }
}
