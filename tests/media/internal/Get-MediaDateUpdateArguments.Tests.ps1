# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>
<#
.SYNOPSIS
    Unit tests for media\internal\Get-MediaDateUpdateArguments.ps1.

.DESCRIPTION
    Verifies that only missing or mismatched embedded date tags are returned.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\ConvertTo-QuotedArgument.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Invoke-MediaTool.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Get-MediaDateUpdateArguments.ps1')
}

Describe 'Get-MediaDateUpdateArguments' {
    It 'returns no write arguments when all supported date tags already match' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{
                ExitCode = 0
                StdOut = '[{"EXIF:DateTimeOriginal":"2021-06-07 08:09:10","EXIF:CreateDate":"2021-06-07 08:09:10","EXIF:ModifyDate":"2021-06-07 08:09:10","QuickTime:MediaCreateDate":"2021-06-07 08:09:10","QuickTime:MediaModifyDate":"2021-06-07 08:09:10","QuickTime:TrackCreateDate":"2021-06-07 08:09:10","QuickTime:TrackModifyDate":"2021-06-07 08:09:10"}]'
                StdErr = ''
            }
        }
        $result = @(Get-MediaDateUpdateArguments -Path 'media.mov' `
            -DateTime ([datetime]'2021-06-07T08:09:10') -ExifToolPath 'exiftool.exe')

        $result.Count | Should -Be 0
        Should -Invoke Invoke-MediaTool -Times 1 -ParameterFilter { $Arguments -contains '-j' }
    }

    It 'returns only the tag whose current value differs' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{
                ExitCode = 0
                StdOut = '[{"EXIF:DateTimeOriginal":"2020-01-02 03:04:05","EXIF:CreateDate":"2021-06-07 08:09:10","EXIF:ModifyDate":"2021-06-07 08:09:10","QuickTime:MediaCreateDate":"2021-06-07 08:09:10","QuickTime:MediaModifyDate":"2021-06-07 08:09:10","QuickTime:TrackCreateDate":"2021-06-07 08:09:10","QuickTime:TrackModifyDate":"2021-06-07 08:09:10"}]'
                StdErr = ''
            }
        }

        $result = @(Get-MediaDateUpdateArguments -Path 'media.mov' `
            -DateTime ([datetime]'2021-06-07T08:09:10') -ExifToolPath 'exiftool.exe')

        $result | Should -Be @('-DateTimeOriginal=2021-06-07 08:09:10')
    }

    It 'returns an assignment for each missing supported date tag' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{ ExitCode = 0; StdOut = '{}'; StdErr = '' }
        }

        $result = @(Get-MediaDateUpdateArguments -Path 'media.mov' `
            -DateTime ([datetime]'2021-06-07T08:09:10') -ExifToolPath 'exiftool.exe')

        $result.Count | Should -Be 7
        $result | Should -Contain '-DateTimeOriginal=2021-06-07 08:09:10'
        $result | Should -Contain '-TrackModifyDate=2021-06-07 08:09:10'
    }
}
