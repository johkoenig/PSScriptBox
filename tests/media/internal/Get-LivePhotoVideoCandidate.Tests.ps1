<#
.SYNOPSIS
    Unit tests for media\internal\Get-LivePhotoVideoCandidate.ps1.

.DESCRIPTION
    Creates temporary fixtures under TestDrive to verify Live Photo pairing.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Get-LivePhotoVideoCandidate.ps1')

    function script:New-LivePhotoFixture
    {
        param([Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][string[]] $RelativePaths)
        $root = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        foreach ($relativePath in $RelativePaths)
        {
            $fullPath = Join-Path $root $relativePath
            $parent = Split-Path -Parent $fullPath
            if (-not (Test-Path -LiteralPath $parent))
            {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            New-Item -ItemType File -Path $fullPath -Force | Out-Null
        }
        return $root
    }
}

Describe 'Get-LivePhotoVideoCandidate' {
    It 'matches MOV files with a same-name JPG in the same folder' {
        $root = New-LivePhotoFixture -Name 'matching-pair' -RelativePaths @(
            'live.mov', 'live.jpg', 'regular.mov', 'other.jpg'
        )

        $candidates = @(Get-LivePhotoVideoCandidate -RootPath $root)
        $candidates.Count | Should -Be 1
        $candidates[0].VideoFile.Name | Should -Be 'live.mov'
        $candidates[0].PhotoFile.Name | Should -Be 'live.jpg'
    }

    It 'searches nested folders and pairs files only within the same folder' {
        $root = New-LivePhotoFixture -Name 'nested-pairs' -RelativePaths @(
            'root.mov',
            'nested\live.mov', 'nested\live.jpg',
            'different-folder\photo.jpg'
        )

        $candidates = @(Get-LivePhotoVideoCandidate -RootPath $root)
        $candidates.Count | Should -Be 1
        $candidates[0].VideoFile.FullName | Should -Be (Join-Path $root 'nested\live.mov')
    }

    It 'does not treat JPEG or other image extensions as a matching JPG' {
        $root = New-LivePhotoFixture -Name 'jpg-only' -RelativePaths @(
            'jpeg-only.mov', 'jpeg-only.jpeg',
            'png-only.mov', 'png-only.png'
        )

        @(Get-LivePhotoVideoCandidate -RootPath $root).Count | Should -Be 0
    }

    It 'throws when the root folder does not exist' {
        { Get-LivePhotoVideoCandidate -RootPath (Join-Path $TestDrive 'missing') } |
                Should -Throw '*The specified folder was not found*'
    }
}
