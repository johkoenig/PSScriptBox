# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Get-TesseractTrainingStatus.ps1.

.DESCRIPTION
    Mocks Invoke-SetupProcess so that no Tesseract executable is started. The
    tests cover language-list parsing, tessdata path fallback, and failures.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Invoke-SetupProcess.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-TesseractTrainingStatus.ps1')
    $script:MessagesPath = Join-Path $PSScriptRoot '..\..\..\pdf\l10n\de-DE\Messages.psd1'
}

Describe 'Get-TesseractTrainingStatus' {
    BeforeEach {
        Mock Invoke-SetupProcess {
            [pscustomobject]@{
                ExitCode = 0
                StdOut   = "List of available languages in `"C:\Tess\tessdata`" (3):`neng`ndeu`nosd`r`n"
                StdErr   = ''
            }
        }
    }

    It 'returns the language codes and the tessdata path reported by Tesseract' {
        $status = Get-TesseractTrainingStatus -TesseractPath 'C:\Tess\tesseract.exe'
        $status.CheckSucceeded | Should -BeTrue
        $status.TessdataPath | Should -Be 'C:\Tess\tessdata'
        $status.Languages | Should -Be @('eng', 'deu', 'osd')
    }

    It 'falls back to the tessdata folder next to the executable' {
        Mock Invoke-SetupProcess {
            [pscustomobject]@{ ExitCode = 0; StdOut = "eng`r`n"; StdErr = '' }
        }
        $status = Get-TesseractTrainingStatus -TesseractPath 'C:\Tools\tesseract.exe'
        $status.TessdataPath | Should -Be (Join-Path 'C:\Tools' 'tessdata')
        $status.Languages | Should -Be @('eng')
    }

    It 'reports a failed check with no languages when the command exits non-zero' {
        Mock Invoke-SetupProcess {
            [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'failed' }
        }
        $status = Get-TesseractTrainingStatus -TesseractPath 'C:\Tess\tesseract.exe'
        $status.CheckSucceeded | Should -BeFalse
        $status.Languages | Should -BeNullOrEmpty
        $status.TessdataPath | Should -BeNullOrEmpty
    }

    It 'passes the UI language and messages to the process runner' {
        Get-TesseractTrainingStatus -TesseractPath 'C:\Tess\tesseract.exe' -UiLanguage 'de' `
            -MessagesPath $script:MessagesPath | Out-Null
        Should -Invoke Invoke-SetupProcess -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains '--list-langs' -and $UiLanguage -eq 'de' -and $MessagesPath -eq $script:MessagesPath
        }
    }
}
