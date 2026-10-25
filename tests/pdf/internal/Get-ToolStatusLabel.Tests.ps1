# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Get-ToolStatusLabel.ps1.

.DESCRIPTION
    Pure function tests. No tool is executed.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-ToolStatusLabel.ps1')
}

Describe 'Get-ToolStatusLabel' {
    It 'returns Present when the tool passed its check' {
        Get-ToolStatusLabel -Available $true -Path 'C:\fake\tool.exe' | Should -Be 'Present'
    }

    It 'returns the validation-failure label when a path exists but the check failed' {
        Get-ToolStatusLabel -Available $false -Path 'C:\fake\tool.exe' | Should -Be 'Found but failed its validation check'
    }

    It 'returns Missing when no path was located' {
        Get-ToolStatusLabel -Available $false -Path '' | Should -Be 'Missing'
    }

    It 'returns the German label when the German catalog is supplied' {
        $messages = @{ 'Missing' = 'Fehlt' }
        Get-ToolStatusLabel -Available $false -Path '' -UiLanguage 'de' -Messages $messages | Should -Be 'Fehlt'
    }
}
