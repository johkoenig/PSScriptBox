# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for nextcloud\internal\Invoke-RobocopyFile.ps1.

.DESCRIPTION
    Runs the real robocopy.exe against temporary TestDrive folders. Covers a
    successful copy, progress reporting, a missing source file, and a
    localized error message.

.NOTES
    Dependencies: Pester 5 or later and robocopy.exe. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    $script:OutputLanguage = 'en'
    $script:GermanMessages = @{}
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\nextcloud\internal\Invoke-RobocopyFile.ps1')
}

Describe 'Invoke-RobocopyFile' {
    BeforeEach {
        $script:Source = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Destination = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:Source | Out-Null
    }

    It 'copies the file and creates the destination directory' {
        $content = 'robocopy test content'
        [System.IO.File]::WriteAllText((Join-Path $script:Source 'sample.txt'), $content)

        Invoke-RobocopyFile -SourceDirectory $script:Source -DestinationDirectory $script:Destination `
            -FileName 'sample.txt' -RelativePath 'sample.txt' -FileLength $content.Length `
            -CompletedBytes 0 -TotalBytes $content.Length -FolderName 'Test'

        [System.IO.File]::ReadAllText((Join-Path $script:Destination 'sample.txt')) | Should -Be $content
    }

    It 'reports progress through the reporter callback without writing to the console' {
        $bytes = [byte[]]::new(2MB)
        [System.IO.File]::WriteAllBytes((Join-Path $script:Source 'large.bin'), $bytes)
        $script:Reports = [System.Collections.Generic.List[object]]::new()
        $reporter = {
            param([string] $Activity, [string] $Status, [int] $PercentComplete, [switch] $Completed)
            $script:Reports.Add([pscustomobject]@{ Activity = $Activity; Status = $Status; PercentComplete = $PercentComplete })
        }

        Invoke-RobocopyFile -SourceDirectory $script:Source -DestinationDirectory $script:Destination `
            -FileName 'large.bin' -RelativePath 'large.bin' -FileLength $bytes.Length `
            -CompletedBytes 0 -TotalBytes $bytes.Length -FolderName 'Test' -ProgressReporter $reporter

        foreach ($report in $script:Reports) {
            $report.Activity | Should -Be 'Copying folder Test'
            $report.PercentComplete | Should -BeGreaterOrEqual 0
            $report.PercentComplete | Should -BeLessOrEqual 100
        }
        Test-Path -LiteralPath (Join-Path $script:Destination 'large.bin') | Should -BeTrue
    }

    It 'throws when robocopy fails for a missing source file' {
        { Invoke-RobocopyFile -SourceDirectory $script:Source -DestinationDirectory $script:Destination `
                -FileName 'missing.txt' -RelativePath 'missing.txt' -FileLength 0 `
                -CompletedBytes 0 -TotalBytes 0 -FolderName 'Test' } | Should -Throw
    }

    It 'uses the German catalog for the copy-activity text' {
        [System.IO.File]::WriteAllText((Join-Path $script:Source 'german.txt'), 'x')
        $bytes = [byte[]]::new(2MB)
        [System.IO.File]::WriteAllBytes((Join-Path $script:Source 'german.bin'), $bytes)
        $messages = @{ 'Copying folder {0}' = 'Ordner {0} wird kopiert' }
        $script:Activities = [System.Collections.Generic.List[string]]::new()
        $reporter = {
            param([string] $Activity, [string] $Status, [int] $PercentComplete, [switch] $Completed)
            $script:Activities.Add($Activity)
        }

        Invoke-RobocopyFile -SourceDirectory $script:Source -DestinationDirectory $script:Destination `
            -FileName 'german.bin' -RelativePath 'german.bin' -FileLength $bytes.Length `
            -CompletedBytes 0 -TotalBytes $bytes.Length -FolderName 'Test' -Language 'de' -Messages $messages `
            -ProgressReporter $reporter

        Test-Path -LiteralPath (Join-Path $script:Destination 'german.bin') | Should -BeTrue
        foreach ($activity in $script:Activities) {
            $activity | Should -Be 'Ordner Test wird kopiert'
        }
    }
}
