# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Update-ProcessPath.ps1.

.DESCRIPTION
    The function changes $env:Path, so the original value is saved before the
    tests and restored afterwards. The registry and the real PATH are not read.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Update-ProcessPath.ps1')
    $script:OriginalPath = $env:Path
}

AfterAll {
    $env:Path = $script:OriginalPath
}

Describe 'Update-ProcessPath' {
    It 'joins the machine and user PATH values with the path separator' {
        Update-ProcessPath -MachinePath 'C:\machine' -UserPath 'C:\user'
        $env:Path | Should -Be ('C:\machine' + [System.IO.Path]::PathSeparator + 'C:\user')
    }

    It 'replaces the previous process PATH instead of appending to it' {
        $env:Path = 'C:\old'
        Update-ProcessPath -MachinePath 'C:\new-machine' -UserPath ''
        $env:Path | Should -Not -Match 'C:\\old'
        $env:Path | Should -Match 'C:\\new-machine'
    }
}
