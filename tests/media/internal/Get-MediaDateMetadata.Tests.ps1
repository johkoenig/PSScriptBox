# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for media\internal\Get-MediaDateMetadata.ps1.

.DESCRIPTION
    Mocks ExifTool process results and verifies valid date tags and explicit
    handling of command and JSON failures.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Invoke-MediaTool.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Get-MediaDateMetadata.ps1')
}

Describe 'Get-MediaDateMetadata' {
    It 'keeps file-level and capture dates while excluding per-track timestamps' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{
                ExitCode = 0
                StdOut = ConvertTo-Json -InputObject @{
                    'QuickTime:CreateDate' = '2021:05:06 12:00:00'
                    'EXIF:DateTimeOriginal' = '2021:05:06 12:00:00'
                    'XMP-exif:DateTimeOriginal' = '2021:05:06 12:00:00'
                    'Track3:MediaCreateDate' = '2021:05:06 12:00:00'
                    'Track3:MediaModifyDate' = '2021:05:06 12:00:00'
                    'Track3:TrackCreateDate' = '2021:05:06 12:00:00'
                    'Track3:TrackModifyDate' = '2021:05:06 12:00:00'
                } -Compress
                StdErr = ''
            }
        }

        $result = Get-MediaDateMetadata -Path 'C:\Videos\clip.mov' -ExifToolPath 'C:\Tools\exiftool.exe'
        $result['QuickTime:CreateDate'] | Should -Be '"2021:05:06 12:00:00"'
        $result['EXIF:DateTimeOriginal'] | Should -Be '"2021:05:06 12:00:00"'
        $result['XMP-exif:DateTimeOriginal'] | Should -Be '"2021:05:06 12:00:00"'
        $result.ContainsKey('Track3:MediaCreateDate') | Should -BeFalse
        $result.ContainsKey('Track3:MediaModifyDate') | Should -BeFalse
        $result.ContainsKey('Track3:TrackCreateDate') | Should -BeFalse
        $result.ContainsKey('Track3:TrackModifyDate') | Should -BeFalse
        $result.ContainsKey('SourceFile') | Should -BeFalse
        Should -Invoke Invoke-MediaTool -Times 1 -ParameterFilter {
            $ExecutablePath -eq 'C:\Tools\exiftool.exe' -and
                    $Arguments -contains '-time:all' -and $Arguments -contains '--File:all'
        }
    }

    It 'throws when ExifTool returns a nonzero exit code' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'read failed' }
        }

        { Get-MediaDateMetadata -Path 'clip.mov' -ExifToolPath 'exiftool.exe' } |
                Should -Throw 'ExifTool could not read date metadata*read failed'
    }

    It 'throws when ExifTool returns invalid JSON' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{ ExitCode = 0; StdOut = 'not-json'; StdErr = '' }
        }

        { Get-MediaDateMetadata -Path 'clip.mov' -ExifToolPath 'exiftool.exe' } |
                Should -Throw 'ExifTool returned invalid date metadata*'
    }

    It 'throws when ExifTool returns more than one record' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{ ExitCode = 0; StdOut = '[{},{}]'; StdErr = '' }
        }

        { Get-MediaDateMetadata -Path 'clip.mov' -ExifToolPath 'exiftool.exe' } |
                Should -Throw 'ExifTool returned an unexpected number*'
    }
}
