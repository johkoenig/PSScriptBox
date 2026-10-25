# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Invoke-SetupProcess.ps1.

.DESCRIPTION
    Runs the current PowerShell host and cmd.exe, which exist on every Windows
    machine that runs this suite. No tool from the PDF toolchain is started and
    nothing outside TestDrive is written.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\ConvertTo-QuotedArgument.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Invoke-SetupProcess.ps1')
}

Describe 'Invoke-SetupProcess' {
    It 'returns exit code 0 and the captured standard output' {
        $hostPath = (Get-Process -Id $PID).Path
        $result = Invoke-SetupProcess -FilePath $hostPath -Arguments @('-NoProfile', '-Command', "[Console]::Out.Write('scriptbox-ok')")
        $result.ExitCode | Should -Be 0
        $result.StdOut | Should -Match 'scriptbox-ok'
    }

    It 'returns the non-zero exit code of the process' {
        $hostPath = (Get-Process -Id $PID).Path
        $result = Invoke-SetupProcess -FilePath $hostPath -Arguments @('-NoProfile', '-Command', 'exit 3')
        $result.ExitCode | Should -Be 3
    }

    It 'captures standard error separately from standard output' {
        $hostPath = (Get-Process -Id $PID).Path
        $result = Invoke-SetupProcess -FilePath $hostPath -Arguments @('-NoProfile', '-Command', "[Console]::Error.Write('scriptbox-err')")
        $result.StdErr | Should -Match 'scriptbox-err'
        $result.StdOut | Should -BeNullOrEmpty
    }

    It 'throws when the executable does not exist' {
        { Invoke-SetupProcess -FilePath (Join-Path $TestDrive 'missing-tool.exe') -Arguments @() } | Should -Throw
    }
}
