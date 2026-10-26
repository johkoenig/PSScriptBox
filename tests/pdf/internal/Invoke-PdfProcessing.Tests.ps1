# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Invoke-PdfProcessing.ps1.

.DESCRIPTION
    Uses a nonexistent Python interpreter so processing fails before OCRmyPDF is
    involved. Verifies the result object and the reporter messages. Input PDFs
    are placeholder files under TestDrive.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-FileSha256.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Invoke-PdfProcessing.ps1')

    function script:Invoke-WithDefaults {
        param([System.IO.FileInfo] $Pdf, [scriptblock] $Reporter)
        $arguments = @{
            Pdf                     = $Pdf
            PythonPath              = 'C:\scriptbox-no-such\python.exe'
            Language                = 'deu'
            NoDeskew                = $false
            NoRotationOfPages       = $false
            ReplaceOriginal         = $false
        }
        if ($Reporter) { $arguments.Reporter = $Reporter }
        Invoke-PdfProcessing @arguments
    }
}

Describe 'Invoke-PdfProcessing' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ('run-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Folder -Force | Out-Null
        $script:PdfPath = Join-Path $script:Folder 'scan.pdf'
        [System.IO.File]::WriteAllBytes($script:PdfPath, [System.Text.Encoding]::ASCII.GetBytes('not a real pdf'))
        $script:Pdf = Get-Item -LiteralPath $script:PdfPath
    }

    It 'reports the processing start through the reporter' {
        $reportLog = [System.Collections.Generic.List[string]]::new()
        $reporter = { param($Kind, $Color, $Text) $reportLog.Add("$Kind|$Text") }
        Invoke-WithDefaults -Pdf $script:Pdf -Reporter $reporter | Out-Null
        $reportLog[0] | Should -Be 'Host|Processing: scan.pdf'
    }

    It 'returns a failed result object when the input cannot be checked' {
        $result = Invoke-WithDefaults -Pdf $script:Pdf
        $result.Success | Should -BeFalse
        $result.Skipped | Should -BeFalse
        $result.FilePath | Should -Be $script:Pdf.FullName
        $result.FailureReason | Should -Not -BeNullOrEmpty
    }

    It 'reports the error through the Warning kind of the reporter' {
        $reportLog = [System.Collections.Generic.List[string]]::new()
        $reporter = { param($Kind, $Color, $Text) $reportLog.Add("$Kind|$Text") }
        Invoke-WithDefaults -Pdf $script:Pdf -Reporter $reporter | Out-Null
        @($reportLog | Where-Object { $_ -like 'Warning|Error processing*' }).Count | Should -Be 1
    }

    It 'does not modify the input file on failure' {
        $before = Get-FileSha256 -Path $script:PdfPath
        Invoke-WithDefaults -Pdf $script:Pdf | Out-Null
        Get-FileSha256 -Path $script:PdfPath | Should -Be $before
    }

    It 'works with the default no-op reporter' {
        { Invoke-WithDefaults -Pdf $script:Pdf } | Should -Not -Throw
    }
}
