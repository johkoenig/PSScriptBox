# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for media\internal\Set-MediaFileTimestamp.ps1.

.DESCRIPTION
    Uses a temporary file under TestDrive to verify that all supported
    file-system timestamps are set.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Set-MediaFileTimestamp.ps1')
}

Describe 'Set-MediaFileTimestamp' {
    It 'sets creation, last-write, and last-access timestamps in UTC' {
        $path = Join-Path $TestDrive 'timestamps.mov'
        [System.IO.File]::WriteAllText($path, 'media')
        $timestamp = [datetime]::SpecifyKind([datetime]::new(2021, 5, 6, 12, 30, 0), [System.DateTimeKind]::Utc)

        Set-MediaFileTimestamp -Path $path -CreationTimeUtc $timestamp `
            -LastWriteTimeUtc $timestamp -LastAccessTimeUtc $timestamp
        $file = Get-Item -LiteralPath $path

        $file.CreationTimeUtc | Should -Be $timestamp
        $file.LastWriteTimeUtc | Should -Be $timestamp
        $file.LastAccessTimeUtc | Should -Be $timestamp
    }

    It 'does not change timestamps when WhatIf is requested' {
        $path = Join-Path $TestDrive 'timestamps-whatif.mov'
        [System.IO.File]::WriteAllText($path, 'media')
        $before = Get-Item -LiteralPath $path
        $timestamp = [datetime]::SpecifyKind([datetime]::new(2001, 2, 3, 4, 5, 6), [System.DateTimeKind]::Utc)

        Set-MediaFileTimestamp -Path $path -CreationTimeUtc $timestamp `
            -LastWriteTimeUtc $timestamp -LastAccessTimeUtc $timestamp -WhatIf

        $after = Get-Item -LiteralPath $path
        $after.CreationTimeUtc | Should -Be $before.CreationTimeUtc
        $after.LastWriteTimeUtc | Should -Be $before.LastWriteTimeUtc
    }
}
