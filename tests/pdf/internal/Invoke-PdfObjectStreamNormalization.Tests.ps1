# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>
<#
.SYNOPSIS
    Unit tests for pdf\internal\Invoke-PdfObjectStreamNormalization.ps1.

.DESCRIPTION
    Mocks the Python process to cover status parsing, output validation, and
    error handling without requiring PDF fixtures.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
    . (Join-Path $script:RepoRoot 'common\internal\Get-LocalizedText.ps1')
    . (Join-Path $script:RepoRoot 'common\internal\ConvertTo-QuotedArgument.ps1')
    . (Join-Path $script:RepoRoot 'pdf\internal\Invoke-PythonCommand.ps1')
    . (Join-Path $script:RepoRoot 'pdf\internal\Invoke-PdfObjectStreamNormalization.ps1')

    $script:PythonPath = 'C:\PSScriptBox-python\python.exe'
    $script:InputPath = Join-Path $TestDrive 'source.pdf'
    [System.IO.File]::WriteAllText($script:InputPath, 'source')

    function script:New-PythonResult
    {
        param([int] $ExitCode = 0, [string] $StdOut = '', [string] $StdErr = '')
        [pscustomobject]@{ ExitCode = $ExitCode; StdOut = $StdOut; StdErr = $StdErr }
    }

    function script:New-NormalizationOutput
    {
        param([string] $Path)
        [System.IO.File]::WriteAllText($Path, 'normalized')
    }
}

Describe 'Invoke-PdfObjectStreamNormalization' {
    BeforeEach {
        $script:OutputPath = Join-Path $TestDrive ('normalized-{0}.pdf.part' -f [guid]::NewGuid().ToString('N'))
    }

    It 'rewrites and verifies a PDF with text operators' {
        Mock Invoke-PythonCommand {
            New-NormalizationOutput -Path $Arguments[3]
            New-PythonResult -StdOut "REPAIRED`t2`t2"
        }

        $result = Invoke-PdfObjectStreamNormalization -PythonPath $script:PythonPath `
            -InputPath $script:InputPath -OutputPath $script:OutputPath

        $result.Status | Should -Be 'Repaired'
        $result.PageCount | Should -Be 2
        $result.TextPageCount | Should -Be 2
        $result.OutputPath | Should -Be ([System.IO.Path]::GetFullPath($script:OutputPath))
        Test-Path -LiteralPath $script:OutputPath | Should -BeTrue
        Should -Invoke Invoke-PythonCommand -Times 1 -Exactly -ParameterFilter {
            $PythonPath -eq $script:PythonPath -and
                    $Arguments[0] -eq '-c' -and
                    $Arguments[1] -match 'ObjectStreamMode\.disable' -and
                    $Arguments[1] -match 'has_object_streams' -and
                    $Arguments[2] -eq [System.IO.Path]::GetFullPath($script:InputPath) -and
                    $Arguments[3] -eq [System.IO.Path]::GetFullPath($script:OutputPath) -and
                    $Arguments[4] -eq '0'
        }
    }

    It 'reports when object streams are already disabled' {
        Mock Invoke-PythonCommand { New-PythonResult -StdOut "ALREADY_NORMALIZED`t2`t2" }

        $result = Invoke-PdfObjectStreamNormalization -PythonPath $script:PythonPath `
            -InputPath $script:InputPath -OutputPath $script:OutputPath

        $result.Status | Should -Be 'AlreadyNormalized'
        $result.PageCount | Should -Be 2
        $result.TextPageCount | Should -Be 2
        $result.OutputPath | Should -BeNullOrEmpty
        Test-Path -LiteralPath $script:OutputPath | Should -BeFalse
    }

    It 'checks whether normalization is needed without writing an output' {
        Mock Invoke-PythonCommand { New-PythonResult -StdOut "NEEDS_NORMALIZATION`t2`t2" }

        $result = Invoke-PdfObjectStreamNormalization -PythonPath $script:PythonPath `
            -InputPath $script:InputPath -OutputPath $script:OutputPath -CheckOnly

        $result.Status | Should -Be 'NeedsNormalization'
        $result.PageCount | Should -Be 2
        $result.TextPageCount | Should -Be 2
        $result.OutputPath | Should -BeNullOrEmpty
        Test-Path -LiteralPath $script:OutputPath | Should -BeFalse
        Should -Invoke Invoke-PythonCommand -Times 1 -Exactly -ParameterFilter {
            $Arguments[4] -eq '1'
        }
    }

    It 'returns NoTextLayer without expecting an output file' {
        Mock Invoke-PythonCommand { New-PythonResult -StdOut "NO_TEXT_LAYER`t2`t0" }

        $result = Invoke-PdfObjectStreamNormalization -PythonPath $script:PythonPath `
            -InputPath $script:InputPath -OutputPath $script:OutputPath

        $result.Status | Should -Be 'NoTextLayer'
        $result.PageCount | Should -Be 2
        $result.TextPageCount | Should -Be 0
        $result.OutputPath | Should -BeNullOrEmpty
        Test-Path -LiteralPath $script:OutputPath | Should -BeFalse
    }

    It 'returns Signed without creating an output file' {
        Mock Invoke-PythonCommand { New-PythonResult -StdOut "SIGNED`t2`t2" }

        $result = Invoke-PdfObjectStreamNormalization -PythonPath $script:PythonPath `
            -InputPath $script:InputPath -OutputPath $script:OutputPath

        $result.Status | Should -Be 'Signed'
        Test-Path -LiteralPath $script:OutputPath | Should -BeFalse
    }

    It 'returns Encrypted without creating an output file' {
        Mock Invoke-PythonCommand { New-PythonResult -StdOut 'ENCRYPTED' }

        $result = Invoke-PdfObjectStreamNormalization -PythonPath $script:PythonPath `
            -InputPath $script:InputPath -OutputPath $script:OutputPath

        $result.Status | Should -Be 'Encrypted'
        Test-Path -LiteralPath $script:OutputPath | Should -BeFalse
    }

    It 'reports Python errors using stderr' {
        Mock Invoke-PythonCommand { New-PythonResult -ExitCode 1 -StdErr "broken PDF`r`n" }

        {
            Invoke-PdfObjectStreamNormalization -PythonPath $script:PythonPath `
                -InputPath $script:InputPath -OutputPath $script:OutputPath
        } | Should -Throw -ExpectedMessage 'PDF object-stream normalization failed (exit code 1): broken PDF'
    }

    It 'uses stdout when Python stderr is empty' {
        Mock Invoke-PythonCommand { New-PythonResult -ExitCode 2 -StdOut 'failure detail' }

        {
            Invoke-PdfObjectStreamNormalization -PythonPath $script:PythonPath `
                -InputPath $script:InputPath -OutputPath $script:OutputPath
        } | Should -Throw -ExpectedMessage 'PDF object-stream normalization failed (exit code 2): failure detail'
    }

    It 'rejects malformed Python output' -ForEach @(
        @{ StdOut = '' }
        @{ StdOut = 'unexpected' }
        @{ StdOut = "REPAIRED`t0`t0" }
        @{ StdOut = "REPAIRED`t2`t3" }
        @{ StdOut = "SIGNED`t2" }
        @{ StdOut = "NO_TEXT_LAYER`t2`tx" }
        @{ StdOut = "NO_TEXT_LAYER`t2`t1" }
        @{ StdOut = "ALREADY_NORMALIZED`t2`t0" }
        @{ StdOut = "NEEDS_NORMALIZATION`t2`t2" }
    ) {
        $script:MockStdOut = $StdOut
        Mock Invoke-PythonCommand { New-PythonResult -StdOut $script:MockStdOut }

        {
            Invoke-PdfObjectStreamNormalization -PythonPath $script:PythonPath `
                -InputPath $script:InputPath -OutputPath $script:OutputPath
        } | Should -Throw -ExpectedMessage '*invalid object-stream result*'
    }

    It 'fails if Python reports success but creates no output' {
        Mock Invoke-PythonCommand { New-PythonResult -StdOut "REPAIRED`t2`t2" }

        {
            Invoke-PdfObjectStreamNormalization -PythonPath $script:PythonPath `
                -InputPath $script:InputPath -OutputPath $script:OutputPath
        } | Should -Throw -ExpectedMessage 'The normalized PDF was not created.'
    }

    It 'does not overwrite an existing output file' {
        Mock Invoke-PythonCommand { New-PythonResult }
        [System.IO.File]::WriteAllText($script:OutputPath, 'keep')

        {
            Invoke-PdfObjectStreamNormalization -PythonPath $script:PythonPath `
                -InputPath $script:InputPath -OutputPath $script:OutputPath
        } | Should -Throw -ExpectedMessage 'The output PDF path already exists.'

        Should -Invoke Invoke-PythonCommand -Times 0
        [System.IO.File]::ReadAllText($script:OutputPath) | Should -Be 'keep'
    }

    It 'rejects identical input and output paths' {
        Mock Invoke-PythonCommand { New-PythonResult }

        {
            Invoke-PdfObjectStreamNormalization -PythonPath $script:PythonPath `
                -InputPath $script:InputPath -OutputPath $script:InputPath
        } | Should -Throw -ExpectedMessage 'The input and output PDF paths must be different.'

        Should -Invoke Invoke-PythonCommand -Times 0
    }
}
