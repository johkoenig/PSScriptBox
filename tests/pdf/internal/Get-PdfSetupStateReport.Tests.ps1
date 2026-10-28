# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Get-PdfSetupStateReport.ps1 and Get-ToolStatusLabel.ps1.

.DESCRIPTION
    Uses plain state objects, so no tool is executed. Covers the report line
    order, console colors, the Python scope label, and the German catalog lookup.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-ToolStatusLabel.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-PdfSetupStateReport.ps1')

    function script:New-ReportState {
        param([hashtable] $Overrides = @{})
        $state = [pscustomobject]@{
            ChocolateyPath       = 'C:\fake\choco.exe'
            ChocolateyAvailable  = $true
            PythonPath           = 'C:\fake\python.exe'
            PythonAvailable      = $true
            PythonScope          = 'User'
            OcrMyPdfAvailable    = $true
            PikePdfAvailable     = $true
            TesseractPath        = 'C:\fake\tesseract.exe'
            TesseractAvailable   = $true
            GhostscriptPath      = 'C:\fake\gswin64c.exe'
            GhostscriptAvailable = $true
            TrainingStatus       = [pscustomobject]@{ CheckSucceeded = $true }
        }
        foreach ($key in $Overrides.Keys) { $state.$key = $Overrides[$key] }
        return $state
    }
}

Describe 'Get-PdfSetupStateReport' {
    It 'returns the lines in display order with their colors' {
        $lines = Get-PdfSetupStateReport -State (New-ReportState)
        $lines[0].Text | Should -Be ''
        $lines[0].Color | Should -BeNullOrEmpty
        $lines[1].Text | Should -Be 'Current dependency state:'
        $lines[1].Color | Should -Be 'Cyan'
        $lines[2].Text | Should -Be 'Chocolatey:'
        $lines[2].Color | Should -Be 'DarkCyan'
        ($lines | Where-Object Text -eq '  Chocolatey: Present') | Should -Not -BeNullOrEmpty
        ($lines | Where-Object Text -eq '  Python executable: C:\fake\python.exe') | Should -Not -BeNullOrEmpty
        ($lines | Where-Object Text -eq 'Tesseract:').Color | Should -Be 'DarkCyan'
    }

    It 'labels a user-scope interpreter as Current user' {
        $lines = Get-PdfSetupStateReport -State (New-ReportState)
        ($lines | Where-Object Text -eq '  Python scope: Current user') | Should -Not -BeNullOrEmpty
    }

    It 'labels a machine-scope interpreter as Machine-wide' {
        $lines = Get-PdfSetupStateReport -State (New-ReportState -Overrides @{ PythonScope = 'Machine' })
        ($lines | Where-Object Text -eq '  Python scope: Machine-wide') | Should -Not -BeNullOrEmpty
    }

    It 'marks the packages as not checked and omits the interpreter lines when Python is missing' {
        $state = New-ReportState -Overrides @{ PythonAvailable = $false; PythonPath = $null; OcrMyPdfAvailable = $false; PikePdfAvailable = $false }
        $lines = Get-PdfSetupStateReport -State $state
        ($lines | Where-Object Text -eq '  Python package OCRmyPDF: Not checked (Python is unavailable)') | Should -Not -BeNullOrEmpty
        ($lines | Where-Object Text -like '  Python executable:*') | Should -BeNullOrEmpty
    }

    It 'reports missing packages when Python is available' {
        $state = New-ReportState -Overrides @{ PikePdfAvailable = $false }
        $lines = Get-PdfSetupStateReport -State $state
        ($lines | Where-Object Text -eq '  Python package pikepdf: Missing') | Should -Not -BeNullOrEmpty
    }

    It 'shows the language data result only when training status exists' {
        $withoutStatus = Get-PdfSetupStateReport -State (New-ReportState -Overrides @{ TrainingStatus = $null })
        ($withoutStatus | Where-Object Text -like '  Language data:*') | Should -BeNullOrEmpty

        $failed = Get-PdfSetupStateReport -State (New-ReportState -Overrides @{ TrainingStatus = [pscustomobject]@{ CheckSucceeded = $false } })
        ($failed | Where-Object Text -eq '  Language data: Could not inspect') | Should -Not -BeNullOrEmpty
    }

    It 'uses the German catalog when the UI language is de' {
        $messagesPath = Join-Path $PSScriptRoot '..\..\..\pdf\l10n\de-DE\Messages.psd1'
        $lines = Get-PdfSetupStateReport -State (New-ReportState) -UiLanguage 'de' -MessagesPath $messagesPath
        ($lines | Where-Object Text -eq 'Aktueller Abhängigkeitsstatus:') | Should -Not -BeNullOrEmpty
    }
}
