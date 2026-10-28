# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Start-ElevatedSetup.ps1.

.DESCRIPTION
    Mocks Start-Process, so no UAC prompt appears and no child process starts.
    Mocks Get-ExecutablePath so the real PATH is not read.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\ConvertTo-QuotedArgument.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-ExecutablePath.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Start-ElevatedSetup.ps1')
}

Describe 'Start-ElevatedSetup' {
    BeforeEach {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 7 } }
        Mock Get-ExecutablePath { 'C:\fake\host.exe' }
    }

    It 'starts the script elevated with -ElevatedChild and returns the child exit code' {
        $exitCode = Start-ElevatedSetup -ScriptPath 'C:\fake\Initialize-PdfProcessor.ps1' -EnglishOutput $false
        $exitCode | Should -Be 7
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $Verb -eq 'RunAs' -and $FilePath -eq 'C:\fake\host.exe' -and $ArgumentList -match '-ElevatedChild'
        }
    }

    It 'forwards -EnglishOutput and the runtime Python path when requested' {
        Start-ElevatedSetup -ScriptPath 'C:\fake\setup.ps1' -EnglishOutput $true -RuntimePythonPath 'C:\fake\python.exe' | Out-Null
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $ArgumentList -match '-EnglishOutput' -and $ArgumentList -match '-RuntimePythonPath' -and $ArgumentList -match 'python\.exe'
        }
    }

    It 'omits the optional switches when they are not requested' {
        Start-ElevatedSetup -ScriptPath 'C:\fake\setup.ps1' -EnglishOutput $false | Out-Null
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $ArgumentList -notmatch '-EnglishOutput' -and $ArgumentList -notmatch '-RuntimePythonPath'
        }
    }

    It 'falls back to the host executable in PSHOME when it is not on PATH' {
        Mock Get-ExecutablePath { $null }
        $hostName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
        Start-ElevatedSetup -ScriptPath 'C:\fake\setup.ps1' -EnglishOutput $false | Out-Null
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq (Join-Path $PSHOME $hostName)
        }
    }
}
