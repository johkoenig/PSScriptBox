# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for common\internal\Get-MissingDependencyReport.ps1.

.DESCRIPTION
    Verifies localized report formatting and preservation of actionable guidance.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-MissingDependencyReport.ps1')
}

Describe 'Get-MissingDependencyReport' {
    It 'formats an English dependency report and preserves guidance' {
        $report = Get-MissingDependencyReport -Dependency 'ExifTool' `
            -Guidance 'Download from https://exiftool.org/' `
            -MessageTemplate 'Missing dependency: {0}'

        $report.Dependency | Should -Be 'ExifTool'
        $report.Message | Should -Be 'Missing dependency: ExifTool'
        $report.Guidance | Should -Be 'Download from https://exiftool.org/'
    }

    It 'localizes the dependency message with the supplied catalog' {
        $report = Get-MissingDependencyReport -Dependency 'ExifTool' -Guidance 'Install it.' `
            -MessageTemplate 'Fehlende Abhängigkeit: {0}'

        $report.Message | Should -Be 'Fehlende Abhängigkeit: ExifTool'
        $report.Guidance | Should -Be 'Install it.'
    }

    It 'rejects empty dependency names and guidance' {
        { Get-MissingDependencyReport -Dependency '' -Guidance 'Install it.' -MessageTemplate 'Missing: {0}' } | Should -Throw
        { Get-MissingDependencyReport -Dependency 'ExifTool' -Guidance '' -MessageTemplate 'Missing: {0}' } | Should -Throw
    }
}
