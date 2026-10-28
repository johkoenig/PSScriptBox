# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>
<#
.SYNOPSIS
    Unit tests for media\internal\Get-MediaDateInputFiles.ps1.

.DESCRIPTION
    Verifies recursive discovery of the legacy media formats and invalid-path
    handling.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Get-MediaDateInputFiles.ps1')
}

Describe 'Get-MediaDateInputFiles' {
    It 'recursively discovers supported extensions and returns the base path' {
        $root = Join-Path $TestDrive 'photos'
        $nested = Join-Path $root 'nested'
        $null = New-Item -ItemType Directory -Path $nested
        $null = New-Item -ItemType File -Path (Join-Path $root 'photo.jpg')
        $null = New-Item -ItemType File -Path (Join-Path $nested 'clip.mov')
        $null = New-Item -ItemType File -Path (Join-Path $nested 'notes.txt')

        $result = Get-MediaDateInputFiles -RootPath $root

        $result.BasePath | Should -Be ([System.IO.Path]::GetFullPath($root))
        @($result.Files.Name) | Should -Contain 'photo.jpg'
        @($result.Files.Name) | Should -Contain 'clip.mov'
        @($result.Files.Name) | Should -Not -Contain 'notes.txt'
    }

    It 'throws a localized error when the path is not a folder' {
        {
            Get-MediaDateInputFiles -RootPath (Join-Path $TestDrive 'missing') `
                -UiLanguage 'de' -Messages @{ 'The selected path is not a folder: {0}' = 'Kein Ordner: {0}' }
        } | Should -Throw 'Kein Ordner:*'
    }
}
