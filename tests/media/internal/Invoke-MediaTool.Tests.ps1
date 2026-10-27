# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for media\internal\Invoke-MediaTool.ps1.

.DESCRIPTION
    Runs a short PowerShell child process to verify output capture and checks
    that missing executables raise an error.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\ConvertTo-QuotedArgument.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Invoke-MediaTool.ps1')
}

Describe 'Invoke-MediaTool' {
    It 'captures output and the process exit code' {
        $childExecutable = if ($PSVersionTable.PSEdition -eq 'Core')
        {
            Join-Path $PSHOME 'pwsh.exe'
        }
        else
        {
            Join-Path $PSHOME 'powershell.exe'
        }
        $result = Invoke-MediaTool -ExecutablePath $childExecutable -Arguments @(
            '-NoProfile', '-Command', "Write-Output 'media-tool-test'"
        )
        $result.ExitCode | Should -Be 0
        $result.StdOut | Should -Match 'media-tool-test'
        $result.StdErr | Should -BeNullOrEmpty
    }

    It 'throws when the executable cannot be started' {
        {
            Invoke-MediaTool -ExecutablePath (Join-Path $TestDrive 'missing.exe') -Arguments @('-version')
        } | Should -Throw 'Media tool could not be started*'
    }
}
