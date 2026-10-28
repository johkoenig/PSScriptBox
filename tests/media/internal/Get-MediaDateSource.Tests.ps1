# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>
<#
.SYNOPSIS
    Unit tests for media\internal\Get-MediaDateSource.ps1.

.DESCRIPTION
    Verifies filename precedence, metadata fallback order, and malformed dates.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Invoke-MediaTool.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Get-MediaDateSource.ps1')
}

Describe 'Get-MediaDateSource' {
    It 'prefers the filename date without invoking ExifTool' {
        Mock Invoke-MediaTool { throw 'ExifTool should not be called.' }
        $file = [System.IO.FileInfo](Join-Path $TestDrive '21-06-07 08-09-10 ABCD.mov')

        $result = Get-MediaDateSource -File $file -ExifToolPath 'exiftool.exe'

        $result.DateTime | Should -Be ([datetime]'2021-06-07T08:09:10')
        $result.Source | Should -Be 'filename'
        $result.IsFileNameFormatted | Should -BeTrue
        Should -Invoke Invoke-MediaTool -Times 0
    }

    It 'reports false when a filename date has not reached the full naming pattern' {
        $file = [System.IO.FileInfo](Join-Path $TestDrive '21-06-07 08-09-10 original.mov')

        $result = Get-MediaDateSource -File $file -ExifToolPath 'exiftool.exe'

        $result.Source | Should -Be 'filename'
        $result.IsFileNameFormatted | Should -BeFalse
    }

    It 'does not fall back when a filename date is malformed' {
        $file = [System.IO.FileInfo](Join-Path $TestDrive '21-19-07 08-09-10 ABCD.mov')

        { Get-MediaDateSource -File $file -ExifToolPath 'exiftool.exe' } |
                Should -Throw 'Invalid date in filename*'
    }

    It 'uses the first available metadata date in legacy priority order' {
        Mock Invoke-MediaTool {
            if ($Arguments -contains '-DateTimeOriginal')
            {
                return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
            }
            if ($Arguments -contains '-CreateDate')
            {
                return [pscustomobject]@{ ExitCode = 0; StdOut = "2021-06-07 08:09:10`n"; StdErr = '' }
            }
            return [pscustomobject]@{ ExitCode = 0; StdOut = '2022-01-01 00:00:00'; StdErr = '' }
        }
        $file = [System.IO.FileInfo](Join-Path $TestDrive 'camera.mov')

        $result = Get-MediaDateSource -File $file -ExifToolPath 'exiftool.exe'

        $result.DateTime | Should -Be ([datetime]'2021-06-07T08:09:10')
        $result.Source | Should -Be 'CreateDate'
        $result.IsFileNameFormatted | Should -BeFalse
        Should -Invoke Invoke-MediaTool -Times 2
    }
}
