<#
.SYNOPSIS
    Unit tests for media\internal\Get-EligibleMediaBackup.ps1.

.DESCRIPTION
    Creates temporary fixtures under TestDrive to verify media backup pairing.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Get-EligibleMediaBackup.ps1')

    function script:New-Fixture
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

Describe 'Get-EligibleMediaBackup' {
    It 'matches a MOV backup to the MP4 output' {
        $root = New-Fixture -Name 'mov-to-mp4' -RelativePaths @('clip.mp4', 'clip_orig.mov')

        $eligible = @(Get-EligibleMediaBackup -RootPath $root)
        $eligible.Count | Should -Be 1
        $eligible[0].BackupFile.Name | Should -Be 'clip_orig.mov'
        $eligible[0].ProcessedPath | Should -Be (Join-Path $root 'clip.mp4')
    }

    It 'does not match a MOV backup to a same-extension MOV file' {
        $root = New-Fixture -Name 'mov-only' -RelativePaths @('clip.mov', 'clip_orig.mov')

        @(Get-EligibleMediaBackup -RootPath $root).Count | Should -Be 0
    }

    It 'matches MP4 and JPEG backups to processed files with the same extension' {
        $root = New-Fixture -Name 'same-extension' -RelativePaths @(
            'video.mp4', 'video_orig.mp4',
            'photo.jpg', 'photo_orig.jpg',
            'portrait.jpeg', 'portrait_orig.jpeg'
        )

        $eligible = @(Get-EligibleMediaBackup -RootPath $root)
        $eligible.Count | Should -Be 3
        @($eligible | ForEach-Object { $_.BackupFile.Name }) | Should -Contain 'video_orig.mp4'
        @($eligible | ForEach-Object { $_.BackupFile.Name }) | Should -Contain 'photo_orig.jpg'
        @($eligible | ForEach-Object { $_.BackupFile.Name }) | Should -Contain 'portrait_orig.jpeg'
    }

    It 'ignores unsupported extensions' {
        $root = New-Fixture -Name 'unsupported' -RelativePaths @('file.png', 'file_orig.png')

        @(Get-EligibleMediaBackup -RootPath $root).Count | Should -Be 0
    }
}
