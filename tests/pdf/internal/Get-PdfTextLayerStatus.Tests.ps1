# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Get-PdfTextLayerStatus.ps1.

.DESCRIPTION
    Invoke-PythonCommand is mocked, so the classification and error handling are
    tested without Python. The integration test runs only when a python.exe with
    the pikepdf module is available and is skipped otherwise.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
    . (Join-Path $script:RepoRoot 'common\internal\Get-LocalizedText.ps1')
    . (Join-Path $script:RepoRoot 'pdf\internal\ConvertTo-QuotedArgument.ps1')
    . (Join-Path $script:RepoRoot 'pdf\internal\Invoke-PythonCommand.ps1')
    . (Join-Path $script:RepoRoot 'pdf\internal\Get-PdfTextLayerStatus.ps1')

    $script:PythonPath = 'C:\scriptbox-python\python.exe'
    $script:PdfPath = Join-Path $TestDrive 'sample.pdf'
    New-Item -ItemType File -Path $script:PdfPath -Force | Out-Null
    $script:Pdf = Get-Item -LiteralPath $script:PdfPath

    function script:New-PythonResult {
        param([int] $ExitCode = 0, [string] $StdOut = '', [string] $StdErr = '')
        [pscustomobject]@{ ExitCode = $ExitCode; StdOut = $StdOut; StdErr = $StdErr }
    }

    $script:Python = Get-Command -Name python.exe -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notmatch '\\WindowsApps\\' } | Select-Object -First 1
    $script:HasPikepdf = $false
    if ($script:Python) {
        $script:HasPikepdf = (Invoke-PythonCommand -PythonPath $script:Python.Source -Arguments @('-c', 'import pikepdf')).ExitCode -eq 0
    }
}

Describe 'Get-PdfTextLayerStatus' {
    It 'classifies a PDF whose pages all contain text as TextLayerPresent' {
        Mock Invoke-PythonCommand { New-PythonResult -StdOut "3`t3`r`n" }

        $result = Get-PdfTextLayerStatus -Pdf $script:Pdf -PythonPath $script:PythonPath
        $result.Status | Should -Be 'TextLayerPresent'
        $result.PageCount | Should -Be 3
        $result.TextPageCount | Should -Be 3
        $result.FilePath | Should -Be $script:Pdf.FullName
        $result.Error | Should -BeNullOrEmpty
    }

    It 'classifies a PDF without text operators as NoTextLayer' {
        Mock Invoke-PythonCommand { New-PythonResult -StdOut "4`t0" }

        $result = Get-PdfTextLayerStatus -Pdf $script:Pdf -PythonPath $script:PythonPath
        $result.Status | Should -Be 'NoTextLayer'
        $result.TextPageCount | Should -Be 0
    }

    It 'classifies a PDF with text on only some pages as PartialTextLayer' {
        Mock Invoke-PythonCommand { New-PythonResult -StdOut "4`t2" }

        $result = Get-PdfTextLayerStatus -Pdf $script:Pdf -PythonPath $script:PythonPath
        $result.Status | Should -Be 'PartialTextLayer'
        $result.PageCount | Should -Be 4
        $result.TextPageCount | Should -Be 2
    }

    It 'passes the Python path and the PDF path to the Python command' {
        Mock Invoke-PythonCommand { New-PythonResult -StdOut "1`t1" }

        Get-PdfTextLayerStatus -Pdf $script:Pdf -PythonPath $script:PythonPath | Out-Null
        Should -Invoke Invoke-PythonCommand -Times 1 -Exactly -ParameterFilter {
            $PythonPath -eq $script:PythonPath -and $Arguments[0] -eq '-c' -and $Arguments[2] -eq $script:Pdf.FullName
        }
    }

    It 'throws with the error stream when Python exits with an error' {
        Mock Invoke-PythonCommand { New-PythonResult -ExitCode 1 -StdErr "boom`r`n" -StdOut 'ignored' }

        { Get-PdfTextLayerStatus -Pdf $script:Pdf -PythonPath $script:PythonPath } |
            Should -Throw -ExpectedMessage 'PDF check failed (exit code 1): boom'
    }

    It 'uses the standard output for the error details when the error stream is empty' {
        Mock Invoke-PythonCommand { New-PythonResult -ExitCode 2 -StdOut 'detail text' }

        { Get-PdfTextLayerStatus -Pdf $script:Pdf -PythonPath $script:PythonPath } |
            Should -Throw -ExpectedMessage 'PDF check failed (exit code 2): detail text'
    }

    It 'uses the German catalog entry for the error message when German output is selected' {
        Mock Invoke-PythonCommand { New-PythonResult -ExitCode 1 -StdErr 'boom' }
        $messages = @{ 'PDF check failed (exit code {0}): {1}' = 'DE: check failed ({0}): {1}' }

        { Get-PdfTextLayerStatus -Pdf $script:Pdf -PythonPath $script:PythonPath -UiLanguage 'de' -Messages $messages } |
            Should -Throw -ExpectedMessage 'DE: check failed (1): boom'
    }

    It 'passes the language selection through to the Python command' {
        Mock Invoke-PythonCommand { New-PythonResult -StdOut "1`t1" }

        Get-PdfTextLayerStatus -Pdf $script:Pdf -PythonPath $script:PythonPath -UiLanguage 'de' -Messages @{} | Out-Null
        Should -Invoke Invoke-PythonCommand -Times 1 -Exactly -ParameterFilter { $UiLanguage -eq 'de' }
    }

    It 'throws when the output does not contain two numbers separated by a tab' -ForEach @(
        @{ StdOut = 'garbage' }
        @{ StdOut = '1' }
        @{ StdOut = "a`tb" }
        @{ StdOut = "1`t2`t3" }
    ) {
        $script:MockStdOut = $StdOut
        Mock Invoke-PythonCommand { New-PythonResult -StdOut $script:MockStdOut }

        { Get-PdfTextLayerStatus -Pdf $script:Pdf -PythonPath $script:PythonPath } |
            Should -Throw -ExpectedMessage '*invalid check result*'
    }

    It 'throws when the PDF contains no pages' {
        Mock Invoke-PythonCommand { New-PythonResult -StdOut "0`t0" }

        { Get-PdfTextLayerStatus -Pdf $script:Pdf -PythonPath $script:PythonPath } |
            Should -Throw -ExpectedMessage '*contains no pages*'
    }

    It 'classifies a real blank PDF as NoTextLayer' {
        if (-not $script:HasPikepdf) { Set-ItResult -Skipped -Because 'python with pikepdf is not available'; return }
        $blankPath = Join-Path $TestDrive 'blank.pdf'
        $creator = 'import pikepdf,sys; p = pikepdf.new(); p.add_blank_page(); p.save(sys.argv[1])'
        (Invoke-PythonCommand -PythonPath $script:Python.Source -Arguments @('-c', $creator, $blankPath)).ExitCode | Should -Be 0

        $result = Get-PdfTextLayerStatus -Pdf (Get-Item -LiteralPath $blankPath) -PythonPath $script:Python.Source
        $result.Status | Should -Be 'NoTextLayer'
        $result.PageCount | Should -Be 1
    }
}
