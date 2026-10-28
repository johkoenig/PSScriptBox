# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for media\internal\Get-MediaInputFile.ps1.

.DESCRIPTION
    Builds a small media folder tree under TestDrive and verifies file
    discovery and path validation without accessing user media.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Get-MediaInputFile.ps1')

    $script:Root = Join-Path $TestDrive 'input'
    New-Item -ItemType Directory -Path (Join-Path $script:Root 'sub') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'a.mov') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'a_orig.mov') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'b.mp4') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'b_orig.mp4') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'note.avi') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'photo.jpg') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'photo_orig.jpeg') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'portrait.JPEG') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'sub\c.MOV') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'sub\d.MP4') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $script:Root 'sub\e.JpG') -Force | Out-Null
}

Describe 'Get-MediaInputFile' {
    It 'finds supported media files recursively and excludes original backups and other formats' {
        $result = Get-MediaInputFile -Path $script:Root
        ($result.Files.Name | Sort-Object) | Should -Be @('a.mov', 'b.mp4', 'c.MOV', 'd.MP4', 'e.JpG', 'photo.jpg', 'portrait.JPEG')
        $result.BasePath | Should -Be (Get-Item -LiteralPath $script:Root).FullName
    }

    It 'returns one MP4 file with its parent folder as the base path' {
        $result = Get-MediaInputFile -Path (Join-Path $script:Root 'b.mp4')
        $result.Files.Count | Should -Be 1
        $result.Files[0].Name | Should -Be 'b.mp4'
        $result.BasePath | Should -Be (Get-Item -LiteralPath $script:Root).FullName
    }

    It 'returns a directly selected JPEG file' {
        $path = Join-Path $script:Root 'portrait.JPEG'

        $result = Get-MediaInputFile -Path $path

        $result.Files.Count | Should -Be 1
        $result.Files[0].Name | Should -Be 'portrait.JPEG'
        $result.BasePath | Should -Be (Get-Item -LiteralPath $script:Root).FullName
    }

    It 'excludes an explicitly selected original backup' {
        $result = Get-MediaInputFile -Path (Join-Path $script:Root 'b_orig.mp4')
        $result.Files | Should -BeNullOrEmpty
    }

    It 'trims quotation marks and whitespace from the path' {
        $result = Get-MediaInputFile -Path ('  "' + $script:Root + '"  ')
        $result.Files.Count | Should -Be 7
    }

    It 'throws when the path is blank' {
        { Get-MediaInputFile -Path '   ' } | Should -Throw 'No path was entered.'
    }

    It 'throws when the path does not exist' {
        { Get-MediaInputFile -Path (Join-Path $script:Root 'missing.mov') } | Should -Throw 'Path not found*'
    }

    It 'throws when a selected file is not a supported video format' {
        { Get-MediaInputFile -Path (Join-Path $script:Root 'note.avi') } |
                Should -Throw 'The selected file is not a supported media file*'
    }
}
