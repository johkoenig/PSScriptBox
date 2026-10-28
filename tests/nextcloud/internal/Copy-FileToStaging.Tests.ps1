# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for nextcloud\internal\Copy-FileToStaging.ps1.

.DESCRIPTION
    Covers verified staging and publication, timestamp preservation, progress
    reporting, missing-source cleanup, and localized progress text.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    $script:OutputLanguage = 'en'
    $script:MessagesPath = ''
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-FileSha256.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\nextcloud\internal\Copy-FileToStaging.ps1')
}

Describe 'Copy-FileToStaging' {
    BeforeEach {
        $script:Source = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Destination = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:Source | Out-Null
    }

    It 'copies the file and creates the destination directory' {
        $content = 'staging copy test content'
        [System.IO.File]::WriteAllText((Join-Path $script:Source 'sample.txt'), $content)

        Copy-FileToStaging -SourceDirectory $script:Source -DestinationDirectory $script:Destination `
            -FileName 'sample.txt' -RelativePath 'sample.txt' -FileLength $content.Length `
            -ExpectedHash (Get-FileSha256 -Path (Join-Path $script:Source 'sample.txt')) `
            -CompletedBytes 0 -TotalBytes $content.Length -FolderName 'Test'

        [System.IO.File]::ReadAllText((Join-Path $script:Destination 'sample.txt')) | Should -Be $content
        @(Get-ChildItem -LiteralPath $script:Destination -Filter '*.part' -File -Force).Count | Should -Be 0
    }

    It 'replaces an existing destination only after staging the completed copy' {
        [System.IO.File]::WriteAllText((Join-Path $script:Source 'sample.txt'), 'new content')
        New-Item -ItemType Directory -Path $script:Destination -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $script:Destination 'sample.txt'), 'old content')

        $source = Get-Item -LiteralPath (Join-Path $script:Source 'sample.txt')
        $source.CreationTimeUtc = [datetime]::new(2021, 2, 3, 4, 5, 6, [DateTimeKind]::Utc)
        $source.LastWriteTimeUtc = [datetime]::new(2022, 6, 7, 8, 9, 10, [DateTimeKind]::Utc)
        $expectedHash = Get-FileSha256 -Path (Join-Path $script:Source 'sample.txt')

        Copy-FileToStaging -SourceDirectory $script:Source -DestinationDirectory $script:Destination `
            -FileName 'sample.txt' -RelativePath 'sample.txt' -FileLength 11 `
            -ExpectedHash $expectedHash `
            -CompletedBytes 0 -TotalBytes 11 -FolderName 'Test'

        [System.IO.File]::ReadAllText((Join-Path $script:Destination 'sample.txt')) | Should -Be 'new content'
        (Get-Item -LiteralPath (Join-Path $script:Destination 'sample.txt')).CreationTimeUtc |
                Should -Be $source.CreationTimeUtc
        (Get-Item -LiteralPath (Join-Path $script:Destination 'sample.txt')).LastWriteTimeUtc |
                Should -Be $source.LastWriteTimeUtc
        @(Get-ChildItem -LiteralPath $script:Destination -Filter '*.part' -File -Force).Count | Should -Be 0
    }

    It 'reports progress through the reporter callback without writing to the console' {
        $bytes = [byte[]]::new(2MB)
        [System.IO.File]::WriteAllBytes((Join-Path $script:Source 'large.bin'), $bytes)
        $script:Reports = [System.Collections.Generic.List[object]]::new()
        $reporter = {
            param([string] $Activity, [string] $Status, [int] $PercentComplete, [switch] $Completed)
            $script:Reports.Add([pscustomobject]@{ Activity = $Activity; Status = $Status; PercentComplete = $PercentComplete })
        }

        Copy-FileToStaging -SourceDirectory $script:Source -DestinationDirectory $script:Destination `
            -FileName 'large.bin' -RelativePath 'large.bin' -FileLength $bytes.Length `
            -ExpectedHash (Get-FileSha256 -Path (Join-Path $script:Source 'large.bin')) `
            -CompletedBytes 0 -TotalBytes $bytes.Length -FolderName 'Test' -ProgressReporter $reporter

        foreach ($report in $script:Reports)
        {
            $report.Activity | Should -Be 'Copying folder Test'
            $report.PercentComplete | Should -BeGreaterOrEqual 0
            $report.PercentComplete | Should -BeLessOrEqual 100
        }
        Test-Path -LiteralPath (Join-Path $script:Destination 'large.bin') | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:Destination -Filter '*.part' -File -Force).Count | Should -Be 0
    }

    It 'throws for a missing source file and leaves no staging file' {
        {
            Copy-FileToStaging -SourceDirectory $script:Source -DestinationDirectory $script:Destination `
                -FileName 'missing.txt' -RelativePath 'missing.txt' -FileLength 0 `
                -ExpectedHash 'missing' `
                -CompletedBytes 0 -TotalBytes 0 -FolderName 'Test'
        } | Should -Throw
        @(Get-ChildItem -LiteralPath $script:Destination -Filter '*.part' -File -Force).Count | Should -Be 0
    }

    It 'does not publish a file whose hash does not match the copy plan' {
        [System.IO.File]::WriteAllText((Join-Path $script:Source 'changed.txt'), 'changed')

        {
            Copy-FileToStaging -SourceDirectory $script:Source -DestinationDirectory $script:Destination `
                -FileName 'changed.txt' -RelativePath 'changed.txt' -FileLength 7 `
                -ExpectedHash 'not-the-file-hash' `
                -CompletedBytes 0 -TotalBytes 7 -FolderName 'Test'
        } | Should -Throw -ExpectedMessage '*changed during copy*'

        Test-Path -LiteralPath (Join-Path $script:Destination 'changed.txt') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:Destination -Filter '*.part' -File -Force).Count | Should -Be 0
    }

    It 'uses the German catalog for the copy-activity text' {
        [System.IO.File]::WriteAllText((Join-Path $script:Source 'german.txt'), 'x')
        $bytes = [byte[]]::new(2MB)
        [System.IO.File]::WriteAllBytes((Join-Path $script:Source 'german.bin'), $bytes)
        $messages = Join-Path $PSScriptRoot '..\..\..\nextcloud\l10n\de-DE\Messages.psd1'
        $script:Activities = [System.Collections.Generic.List[string]]::new()
        $reporter = {
            param([string] $Activity, [string] $Status, [int] $PercentComplete, [switch] $Completed)
            $script:Activities.Add($Activity)
        }

        Copy-FileToStaging -SourceDirectory $script:Source -DestinationDirectory $script:Destination `
            -FileName 'german.bin' -RelativePath 'german.bin' -FileLength $bytes.Length `
            -ExpectedHash (Get-FileSha256 -Path (Join-Path $script:Source 'german.bin')) `
            -CompletedBytes 0 -TotalBytes $bytes.Length -FolderName 'Test' -Language 'de' -MessagesPath $messages `
            -ProgressReporter $reporter

        Test-Path -LiteralPath (Join-Path $script:Destination 'german.bin') | Should -BeTrue
        foreach ($activity in $script:Activities)
        {
            $activity | Should -Be 'Kopiere Ordner Test'
        }
    }
}
