# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Invoke-PdfRotationOnly.ps1.

.DESCRIPTION
    Mocks Ghostscript, Tesseract, and Python while checking orientation
    selection, output generation, and failure handling.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\ConvertTo-QuotedArgument.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Invoke-SetupProcess.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Invoke-PythonCommand.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Invoke-PdfRotationOnly.ps1')
}

Describe 'Invoke-PdfRotationOnly' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ('rotation-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Folder -Force | Out-Null
        $script:PdfPath = Join-Path $script:Folder 'scan.pdf'
        [System.IO.File]::WriteAllText($script:PdfPath, 'placeholder PDF')
        $script:Pdf = Get-Item -LiteralPath $script:PdfPath

        Mock Invoke-SetupProcess {
            if ($FilePath -eq 'fake-gs.exe')
            {
                $pattern = ($Arguments | Where-Object { $_ -like '-sOutputFile=*' }) -replace '^-sOutputFile=', ''
                $imagePath = $pattern -replace '%d', '1'
                [System.IO.File]::WriteAllText($imagePath, 'image')
                return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
            }
            return [pscustomobject]@{
                ExitCode = 0
                StdOut = "Orientation in degrees: 90`nRotate: 270`nOrientation confidence: 12.50`n"
                StdErr = ''
            }
        }
        Mock Invoke-PythonCommand {
            [System.IO.File]::WriteAllText($Arguments[3], 'rotated PDF')
            return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }
    }

    It 'applies only confident non-zero page rotations without running OCR' {
        $outputPath = Join-Path $script:Folder 'output.pdf'

        $result = Invoke-PdfRotationOnly -Pdf $script:Pdf -PageCount 1 `
            -PythonPath 'fake-python.exe' -GhostscriptPath 'fake-gs.exe' `
            -TesseractPath 'fake-tesseract.exe' -OutputPath $outputPath

        $result.ChangedPages | Should -Be @(1)
        $result.UndeterminedPages | Should -BeNullOrEmpty
        Test-Path -LiteralPath $outputPath | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:Folder -Directory -Filter '.*.orientation.part' -Force).Count | Should -Be 0
        Should -Invoke Invoke-PythonCommand -Times 1
    }

    It 'leaves pages unchanged when orientation confidence is below the threshold' {
        Mock Invoke-SetupProcess {
            if ($FilePath -eq 'fake-gs.exe')
            {
                $pattern = ($Arguments | Where-Object { $_ -like '-sOutputFile=*' }) -replace '^-sOutputFile=', ''
                [System.IO.File]::WriteAllText(($pattern -replace '%d', '1'), 'image')
                return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
            }
            return [pscustomobject]@{
                ExitCode = 0
                StdOut = "Rotate: 90`nOrientation confidence: 2.00`n"
                StdErr = ''
            }
        }
        $outputPath = Join-Path $script:Folder 'output.pdf'

        $result = Invoke-PdfRotationOnly -Pdf $script:Pdf -PageCount 1 `
            -PythonPath 'fake-python.exe' -GhostscriptPath 'fake-gs.exe' `
            -TesseractPath 'fake-tesseract.exe' -OutputPath $outputPath

        $result.ChangedPages | Should -BeNullOrEmpty
        $result.UndeterminedPages | Should -Be @(1)
        Test-Path -LiteralPath $outputPath | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:Folder -Directory -Filter '.*.orientation.part' -Force).Count | Should -Be 0
        Should -Invoke Invoke-PythonCommand -Times 0
    }

    It 'throws when Ghostscript cannot render the PDF' {
        Mock Invoke-SetupProcess {
            [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'render error' }
        }

        {
            Invoke-PdfRotationOnly -Pdf $script:Pdf -PageCount 1 `
                -PythonPath 'fake-python.exe' -GhostscriptPath 'fake-gs.exe' `
                -TesseractPath 'fake-tesseract.exe' -OutputPath (Join-Path $script:Folder 'output.pdf')
        } | Should -Throw '*render error*'
    }
}
