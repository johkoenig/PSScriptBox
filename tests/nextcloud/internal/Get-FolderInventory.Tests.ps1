# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for nextcloud\internal\Get-FolderInventory.ps1.

.DESCRIPTION
    Builds small folder trees in TestDrive and checks listed files, sizes,
    subdirectories, and the excluded-name filters.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\nextcloud\internal\Get-FolderInventory.ps1')
}

Describe 'Get-FolderInventory' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $script:Root 'sub') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $script:Root 'a.txt'), '12345')
        [System.IO.File]::WriteAllText((Join-Path $script:Root 'sub\b.txt'), '123')
    }

    It 'lists files with relative paths and sizes' {
        $inventory = Get-FolderInventory -Path $script:Root
        $inventory.Files.RelativePath | Should -Contain 'a.txt'
        $inventory.Files.RelativePath | Should -Contain 'sub\b.txt'
        $inventory.TotalBytes | Should -Be 8
    }

    It 'lists subdirectories' {
        (Get-FolderInventory -Path $script:Root).Directories | Should -Contain 'sub'
    }

    It 'skips the default excluded names' {
        [System.IO.File]::WriteAllText((Join-Path $script:Root 'desktop.ini'), 'x')
        [System.IO.File]::WriteAllText((Join-Path $script:Root 'Thumbs.db'), 'x')
        $names = (Get-FolderInventory -Path $script:Root).Files.RelativePath
        $names | Should -Not -Contain 'desktop.ini'
        $names | Should -Not -Contain 'Thumbs.db'
    }

    It 'honors a custom excluded name list' {
        [System.IO.File]::WriteAllText((Join-Path $script:Root 'skip.me'), 'x')
        $names = (Get-FolderInventory -Path $script:Root -ExcludedNames 'skip.me').Files.RelativePath
        $names | Should -Not -Contain 'skip.me'
        $names | Should -Contain 'a.txt'
    }

    It 'returns empty collections for an empty folder' {
        $empty = Join-Path $TestDrive 'empty-folder'
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
        $inventory = Get-FolderInventory -Path $empty
        @($inventory.Files).Count | Should -Be 0
        $inventory.TotalBytes | Should -Be 0
    }
}
