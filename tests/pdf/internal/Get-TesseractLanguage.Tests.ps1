# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Get-TesseractLanguage.ps1.

.DESCRIPTION
    Mocks Invoke-Tesseract so the --list-langs output is controlled. Tesseract
    itself is not required.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Invoke-Tesseract.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-TesseractLanguage.ps1')
}

Describe 'Get-TesseractLanguage' {
    It 'parses language codes and the tessdata folder from the header' {
        Mock Invoke-Tesseract {
            [pscustomobject]@{
                ExitCode = 0
                StdOut   = "List of available languages in `"C:\Tess\tessdata`" (2):`r`neng`r`ndeu`r`n"
                StdErr   = ''
            }
        }
        $result = Get-TesseractLanguage -TesseractPath 'C:\Tess\tesseract.exe'
        $result.Languages | Should -Be @('eng', 'deu')
        $result.TessdataPath | Should -Be 'C:\Tess\tessdata'
    }

    It 'falls back to a tessdata folder next to the executable when the header is missing' {
        Mock Invoke-Tesseract {
            [pscustomobject]@{ ExitCode = 0; StdOut = "eng`r`n"; StdErr = '' }
        }
        $result = Get-TesseractLanguage -TesseractPath 'C:\Tess\tesseract.exe'
        $result.Languages | Should -Be @('eng')
        $result.TessdataPath | Should -Be (Join-Path 'C:\Tess' 'tessdata')
    }

    It 'throws with the stderr text when --list-langs fails' {
        Mock Invoke-Tesseract {
            [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'boom' }
        }
        { Get-TesseractLanguage -TesseractPath 'C:\Tess\tesseract.exe' } |
            Should -Throw 'Tesseract --list-langs failed: boom'
    }

    It 'passes the --list-langs argument to Invoke-Tesseract' {
        Mock Invoke-Tesseract {
            [pscustomobject]@{ ExitCode = 0; StdOut = "eng`r`n"; StdErr = '' }
        }
        Get-TesseractLanguage -TesseractPath 'C:\Tess\tesseract.exe' | Out-Null
        Should -Invoke Invoke-Tesseract -Times 1 -ParameterFilter { $Arguments -eq '--list-langs' }
    }
}
