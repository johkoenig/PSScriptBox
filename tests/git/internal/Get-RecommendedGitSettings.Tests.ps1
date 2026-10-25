# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Get-RecommendedGitSettings.ps1.

.DESCRIPTION
    Checks the shape and order of the static recommended-settings catalog.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-RecommendedGitSettings.ps1')
}

Describe 'Get-RecommendedGitSettings' {
    It 'returns the eight catalog entries in display order' {
        $keys = @(Get-RecommendedGitSettings | ForEach-Object { $_.Key })
        $keys -join ',' | Should -Be 'init.defaultBranch,core.autocrlf,core.longpaths,fetch.prune,pull.rebase,push.autoSetupRemote,format.signOff,alias.cs'
    }

    It 'gives every entry a recommended value, a description, and options' {
        foreach ($setting in Get-RecommendedGitSettings) {
            $setting.Value | Should -Not -BeNullOrEmpty
            $setting.Description | Should -Not -BeNullOrEmpty
            @($setting.Options).Count | Should -BeGreaterThan 0
        }
    }

    It 'allows custom values only for init.defaultBranch and alias.cs' {
        $custom = @(Get-RecommendedGitSettings | Where-Object { $_.ContainsKey('AllowCustom') -and $_.AllowCustom } | ForEach-Object { $_.Key })
        $custom -join ',' | Should -Be 'init.defaultBranch,alias.cs'
    }

    It 'recommends the value true for core.autocrlf' {
        $setting = Get-RecommendedGitSettings | Where-Object { $_.Key -eq 'core.autocrlf' }
        $setting.Value | Should -Be 'true'
    }
}
