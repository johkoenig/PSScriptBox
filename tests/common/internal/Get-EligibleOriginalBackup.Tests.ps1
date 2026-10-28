<#
.SYNOPSIS
    Unit tests for common\internal\Get-EligibleOriginalBackup.ps1.

.DESCRIPTION
    Creates temporary fixtures under TestDrive to verify backup pairing.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-EligibleOriginalBackup.ps1')

    function script:New-Fixture
    {
        param(
            [Parameter(Mandatory)][string] $Name,
            [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $RelativePaths
        )
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

Describe 'Get-EligibleOriginalBackup' {
    It 'pairs a backup with a processed file using the same extension by default' {
        $root = New-Fixture -Name 'same-extension' -RelativePaths @('scan.pdf', 'scan_orig.pdf')

        $eligible = @(Get-EligibleOriginalBackup -RootPath $root -Extensions @('.pdf'))
        $eligible.Count | Should -Be 1
        $eligible[0].BackupFile.Name | Should -Be 'scan_orig.pdf'
        $eligible[0].ProcessedPath | Should -Be (Join-Path $root 'scan.pdf')
    }

    It 'uses the mapped processed extension when the workflow changes file types' {
        $root = New-Fixture -Name 'mapped-extension' -RelativePaths @('clip.mp4', 'clip_orig.mov')

        $eligible = @(Get-EligibleOriginalBackup -RootPath $root -Extensions @('.mov') -ProcessedExtensionMap @{ '.mov' = '.mp4' })
        $eligible.Count | Should -Be 1
        $eligible[0].BackupFile.Name | Should -Be 'clip_orig.mov'
        $eligible[0].ProcessedPath | Should -Be (Join-Path $root 'clip.mp4')
    }

    It 'skips a backup when its corresponding processed file is missing' {
        $root = New-Fixture -Name 'missing-processed' -RelativePaths @('lonely_orig.pdf')

        @(Get-EligibleOriginalBackup -RootPath $root -Extensions @('.pdf')).Count | Should -Be 0
    }

    It 'requires the processed file to be in the same folder' {
        $root = New-Fixture -Name 'same-folder' -RelativePaths @('sub\scan_orig.pdf', 'scan.pdf')

        @(Get-EligibleOriginalBackup -RootPath $root -Extensions @('.pdf')).Count | Should -Be 0
    }

    It 'searches subfolders recursively' {
        $root = New-Fixture -Name 'nested' -RelativePaths @('sub\deep\invoice.pdf', 'sub\deep\invoice_orig.pdf')

        $eligible = @(Get-EligibleOriginalBackup -RootPath $root -Extensions @('.pdf'))
        $eligible.Count | Should -Be 1
        $eligible[0].BackupFile.FullName | Should -Be (Join-Path $root 'sub\deep\invoice_orig.pdf')
    }

    It 'matches extensions and the _orig suffix case-insensitively' {
        $root = New-Fixture -Name 'case' -RelativePaths @('Report.PDF', 'REPORT_ORIG.pdf')

        @(Get-EligibleOriginalBackup -RootPath $root -Extensions @('.pdf')).Count | Should -Be 1
    }

    It 'ignores extensions not requested' {
        $root = New-Fixture -Name 'extension' -RelativePaths @('notes.txt', 'notes_orig.txt', 'image_orig.png', 'image.png')

        @(Get-EligibleOriginalBackup -RootPath $root -Extensions @('.pdf')).Count | Should -Be 0
    }

    It 'ignores a processed path that is a folder instead of a file' {
        $root = New-Fixture -Name 'processed-folder' -RelativePaths @('folder_orig.pdf')
        New-Item -ItemType Directory -Path (Join-Path $root 'folder.pdf') | Out-Null

        @(Get-EligibleOriginalBackup -RootPath $root -Extensions @('.pdf')).Count | Should -Be 0
    }

    It 'includes hidden original backups' {
        $root = New-Fixture -Name 'hidden' -RelativePaths @('hidden.pdf', 'hidden_orig.pdf')
        (Get-Item -LiteralPath (Join-Path $root 'hidden_orig.pdf')).Attributes = 'Hidden'

        @(Get-EligibleOriginalBackup -RootPath $root -Extensions @('.pdf')).Count | Should -Be 1
    }

    It 'returns nothing for an empty folder' {
        $root = New-Fixture -Name 'empty' -RelativePaths @()

        @(Get-EligibleOriginalBackup -RootPath $root -Extensions @('.pdf')).Count | Should -Be 0
    }
}
