# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Test-PythonModule.ps1.

.DESCRIPTION
    Uses a nonexistent interpreter for the failure path and the real Python
    interpreter, when available, for module imports. Python-dependent tests are
    skipped when Python is not usable.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Test-PythonModule.ps1')

    $script:PythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
    $script:PythonUsable = $false
    if ($script:PythonPath) {
        # The Microsoft Store alias throws instead of exiting, so the probe must catch it.
        try {
            & $script:PythonPath -c 'import os' *> $null
            $script:PythonUsable = ($LASTEXITCODE -eq 0)
        }
        catch { $script:PythonUsable = $false }
    }
}

Describe 'Test-PythonModule' {
    It 'returns $false when the interpreter cannot be started' {
        Test-PythonModule -PythonPath 'C:\scriptbox-no-such\python.exe' -ModuleName 'os' | Should -BeFalse
    }

    It 'returns $true for an importable standard module' {
        if (-not $script:PythonUsable) { Set-ItResult -Skipped -Because 'Python is not available'; return }
        Test-PythonModule -PythonPath $script:PythonPath -ModuleName 'os' | Should -BeTrue
    }

    It 'returns $false for a module that does not exist' {
        if (-not $script:PythonUsable) { Set-ItResult -Skipped -Because 'Python is not available'; return }
        Test-PythonModule -PythonPath $script:PythonPath -ModuleName 'scriptbox_no_such_module_xyz' | Should -BeFalse
    }
}
