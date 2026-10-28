# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Get-PdfPythonRuntime.ps1.

.DESCRIPTION
    Covers the interpreter discovery and scope classification. Python-based
    tests are skipped when no python.exe outside the Windows Store alias folder
    is available. Command discovery is mocked, so no test depends on the
    installed Python layout.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
    . (Join-Path $script:RepoRoot 'pdf\internal\Get-PdfPythonRuntime.ps1')
    $script:PowerShellExe = (Get-Command -Name powershell.exe -CommandType Application).Source
    $script:Python = Get-Command -Name python.exe -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notmatch '\\WindowsApps\\' } | Select-Object -First 1
}

Describe 'Invoke-PdfPythonProbe' {
    It 'returns the exit code and standard output of the process' {
        $result = Invoke-PdfPythonProbe -FilePath $script:PowerShellExe -Arguments @('-NoProfile', '-Command', 'Write-Output hello; exit 3')
        $result.ExitCode | Should -Be 3
        $result.StdOut.Trim() | Should -Be 'hello'
    }

    It 'returns -1 and the error message when the executable does not exist' {
        $result = Invoke-PdfPythonProbe -FilePath 'C:\PSScriptBox-missing\python.exe' -Arguments @('-c', 'print(1)')
        $result.ExitCode | Should -Be -1
        $result.StdErr | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-PdfPythonRuntime' {
    It 'returns $null when no interpreter command is found' {
        Mock Get-Command { @() }
        Get-PdfPythonRuntime | Should -BeNullOrEmpty
    }

    It 'skips python.exe Windows Store aliases without probing them' {
        Mock Get-Command {
            [pscustomobject]@{
                CommandType = [System.Management.Automation.CommandTypes]::Application
                Source      = 'C:\Users\x\AppData\Local\Microsoft\WindowsApps\python.exe'
            }
        } -ParameterFilter { $Name -eq 'python.exe' }
        Mock Get-Command { @() } -ParameterFilter { $Name -ne 'python.exe' }
        Mock Invoke-PdfPythonProbe { [pscustomobject]@{ ExitCode = -1; StdOut = ''; StdErr = '' } }

        Get-PdfPythonRuntime | Should -BeNullOrEmpty
        Should -Invoke Invoke-PdfPythonProbe -Times 0 -Exactly -ParameterFilter { $FilePath -like '*WindowsApps*' }
    }

    It 'probes each discovered candidate once and returns $null when all fail' {
        Mock Get-Command {
            [pscustomobject]@{
                CommandType = [System.Management.Automation.CommandTypes]::Application
                Source      = $script:PowerShellExe
            }
        }
        Mock Invoke-PdfPythonProbe { [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'failed' } }

        Get-PdfPythonRuntime | Should -BeNullOrEmpty
        Should -Invoke Invoke-PdfPythonProbe -Times 2 -Exactly
    }

    It 'returns $null for a preferred interpreter that does not report Python 3' {
        Get-PdfPythonRuntime -PreferredPath $script:PowerShellExe | Should -BeNullOrEmpty
    }

    It 'returns $null for a preferred path that does not exist' {
        Get-PdfPythonRuntime -PreferredPath 'C:\PSScriptBox-missing\python.exe' | Should -BeNullOrEmpty
    }

    It 'reports the explicit path discovery for a valid preferred interpreter' {
        if (-not $script:Python) { Set-ItResult -Skipped -Because 'no python.exe available'; return }
        $runtime = Get-PdfPythonRuntime -PreferredPath $script:Python.Source
        $runtime.Discovery | Should -Be 'Explicit path'
        Test-Path -LiteralPath $runtime.Path -PathType Leaf | Should -BeTrue
    }

    It 'classifies an interpreter inside a user root as User scope' {
        if (-not $script:Python) { Set-ItResult -Skipped -Because 'no python.exe available'; return }
        $userRoot = Split-Path -Parent $script:Python.Source
        $runtime = Get-PdfPythonRuntime -PreferredPath $script:Python.Source -UserRoots @($userRoot)
        $runtime.Scope | Should -Be 'User'
    }

    It 'classifies an interpreter outside the given user roots as Machine scope' {
        if (-not $script:Python) { Set-ItResult -Skipped -Because 'no python.exe available'; return }
        $runtime = Get-PdfPythonRuntime -PreferredPath $script:Python.Source -UserRoots @('C:\PSScriptBox-no-such-root')
        $runtime.Scope | Should -Be 'Machine'
    }
}
