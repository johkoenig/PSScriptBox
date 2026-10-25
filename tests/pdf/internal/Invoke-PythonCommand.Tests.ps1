# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Invoke-PythonCommand.ps1.

.DESCRIPTION
    Runs real processes instead of mocks: cmd.exe and powershell.exe are used as
    generic executables that exist on every Windows system. No Python
    installation is required.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
    . (Join-Path $script:RepoRoot 'common\internal\Get-LocalizedText.ps1')
    . (Join-Path $script:RepoRoot 'pdf\internal\ConvertTo-QuotedArgument.ps1')
    . (Join-Path $script:RepoRoot 'pdf\internal\Invoke-PythonCommand.ps1')
    $script:PowerShellExe = (Get-Command -Name powershell.exe -CommandType Application).Source
}

Describe 'Invoke-PythonCommand' {
    It 'returns the standard output and a zero exit code' {
        $result = Invoke-PythonCommand -PythonPath $script:PowerShellExe -Arguments @('-NoProfile', '-Command', 'Write-Output hello')
        $result.ExitCode | Should -Be 0
        $result.StdOut.Trim() | Should -Be 'hello'
        $result.StdErr | Should -BeNullOrEmpty
    }

    It 'returns the exit code of the process' {
        $result = Invoke-PythonCommand -PythonPath $script:PowerShellExe -Arguments @('-NoProfile', '-Command', 'exit 3')
        $result.ExitCode | Should -Be 3
    }

    It 'returns the standard error stream separately from standard output' {
        $result = Invoke-PythonCommand -PythonPath $script:PowerShellExe -Arguments @(
            '-NoProfile', '-Command', '[Console]::Error.WriteLine(''failure text''); [Console]::Out.WriteLine(''ok''); exit 2'
        )
        $result.ExitCode | Should -Be 2
        $result.StdErr.Trim() | Should -Be 'failure text'
        $result.StdOut.Trim() | Should -Be 'ok'
    }

    It 'throws when the executable does not exist' {
        { Invoke-PythonCommand -PythonPath 'C:\scriptbox-missing\python.exe' -Arguments @('-c', 'print(1)') } |
            Should -Throw
    }
}
