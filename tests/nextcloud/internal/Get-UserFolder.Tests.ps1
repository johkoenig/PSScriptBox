# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for nextcloud\internal\Get-UserFolder.ps1.

.DESCRIPTION
    Passes the folder paths explicitly through -FolderPaths, so the tests use
    TestDrive folders instead of real Windows profile folders.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\nextcloud\internal\Get-UserFolder.ps1')
    $script:OutputLanguage = 'en'
    $script:MessagesPath = ''

    $script:PicturesPath = Join-Path $TestDrive 'Pictures'
    $script:DocumentsPath = Join-Path $TestDrive 'Documents'
    New-Item -ItemType Directory -Path $script:PicturesPath, $script:DocumentsPath -Force | Out-Null
}

Describe 'Get-UserFolder' {
    It 'maps Pictures to the Photos target folder' {
        $folder = Get-UserFolder -Names 'Pictures' -FolderPaths @{ Pictures = $script:PicturesPath } -Language $script:OutputLanguage -MessagesPath $script:MessagesPath
        $folder.Name | Should -Be 'Pictures'
        $folder.TargetName | Should -Be 'Photos'
        $folder.SourcePath | Should -Be ([System.IO.Path]::GetFullPath($script:PicturesPath))
    }

    It 'keeps the name for other folders' {
        (Get-UserFolder -Names 'Documents' -FolderPaths @{ Documents = $script:DocumentsPath } -Language $script:OutputLanguage -MessagesPath $script:MessagesPath).TargetName | Should -Be 'Documents'
    }

    It 'returns one entry per requested folder that exists' {
        $folders = Get-UserFolder -Names 'Documents', 'Pictures' -FolderPaths @{ Documents = $script:DocumentsPath; Pictures = $script:PicturesPath } -Language $script:OutputLanguage -MessagesPath $script:MessagesPath
        @($folders).Count | Should -Be 2
    }

    It 'skips and warns about a folder whose path does not exist' {
        $missing = Join-Path $TestDrive 'does-not-exist'
        $folders = Get-UserFolder -Names 'Desktop' -FolderPaths @{ Desktop = $missing } -WarningVariable warnings -WarningAction SilentlyContinue -Language $script:OutputLanguage -MessagesPath $script:MessagesPath
        @($folders).Count | Should -Be 0
        "$warnings" | Should -Match 'Desktop'
    }

    It 'skips and warns about a folder without an entry in FolderPaths' {
        $folders = Get-UserFolder -Names 'Videos' -FolderPaths @{ } -WarningVariable warnings -WarningAction SilentlyContinue -Language $script:OutputLanguage -MessagesPath $script:MessagesPath
        @($folders).Count | Should -Be 0
        "$warnings" | Should -Match 'Videos'
    }
}
