# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for nextcloud\internal\Get-UserSpecialFolderPath.ps1.

.DESCRIPTION
    Checks the supported folder names and that each value comes from the
    Windows known-folder lookup. No folder is created or changed.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\nextcloud\internal\Get-UserSpecialFolderPath.ps1')
}

Describe 'Get-UserSpecialFolderPath' {
    It 'returns a key for each supported folder' {
        $paths = Get-UserSpecialFolderPath
        (@($paths.Keys | Sort-Object) -join ',') | Should -Be 'Desktop,Documents,Music,Pictures,Videos'
    }

    It 'returns the Windows known-folder path for each name' {
        $paths = Get-UserSpecialFolderPath
        $paths['Documents'] | Should -Be ([Environment]::GetFolderPath('MyDocuments'))
        $paths['Pictures'] | Should -Be ([Environment]::GetFolderPath('MyPictures'))
        $paths['Desktop'] | Should -Be ([Environment]::GetFolderPath('DesktopDirectory'))
    }
}
