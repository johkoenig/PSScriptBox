# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for media\internal\Set-MediaFileTimestamps.ps1.

.DESCRIPTION
    Uses a temporary file under TestDrive to verify that all supported
    file-system timestamps are set.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Set-MediaFileTimestamps.ps1')
}

Describe 'Set-MediaFileTimestamps' {
    It 'sets creation, last-write, and last-access timestamps in UTC' {
        $path = Join-Path $TestDrive 'timestamps.mov'
        [System.IO.File]::WriteAllText($path, 'media')
        $timestamp = [datetime]::SpecifyKind([datetime]::new(2021, 5, 6, 12, 30, 0), [System.DateTimeKind]::Utc)

        Set-MediaFileTimestamps -Path $path -CreationTimeUtc $timestamp `
            -LastWriteTimeUtc $timestamp -LastAccessTimeUtc $timestamp
        $file = Get-Item -LiteralPath $path

        $file.CreationTimeUtc | Should -Be $timestamp
        $file.LastWriteTimeUtc | Should -Be $timestamp
        $file.LastAccessTimeUtc | Should -Be $timestamp
    }
}
