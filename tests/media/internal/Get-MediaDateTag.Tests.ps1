# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for media\internal\Get-MediaDateTag.ps1.

.DESCRIPTION
    Mocks ExifTool process results and verifies valid date tags and explicit
    handling of command and JSON failures.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Invoke-MediaTool.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Get-MediaDateTag.ps1')
}

Describe 'Get-MediaDateTag' {
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

        $result = Get-MediaDateTag -Path 'C:\Videos\clip.mov' -ExifToolPath 'C:\Tools\exiftool.exe'
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

    It 'excludes non-capture timestamps but keeps standard EXIF capture dates' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{
                ExitCode = 0
                StdOut = ConvertTo-Json -InputObject @{
                    'ExifIFD:DateTimeOriginal' = '2026:09:20 14:40:48'
                    'ExifIFD:CreateDate' = '2026:09:20 14:40:48'
                    'Samsung:TimeStamp' = '2026:09:20 11:10:48.201+02:00'
                    'IFD0:ModifyDate' = '2026:09:20 20:28:06'
                } -Compress
                StdErr = ''
            }
        }

        $result = Get-MediaDateTag -Path 'C:\Photos\photo.jpg' -ExifToolPath 'C:\Tools\exiftool.exe'

        $result.ContainsKey('ExifIFD:DateTimeOriginal') | Should -BeTrue
        $result.ContainsKey('ExifIFD:CreateDate') | Should -BeTrue
        $result.ContainsKey('Samsung:TimeStamp') | Should -BeFalse
        $result.ContainsKey('IFD0:ModifyDate') | Should -BeFalse
    }

    It 'throws when ExifTool returns a nonzero exit code' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'read failed' }
        }

        { Get-MediaDateTag -Path 'clip.mov' -ExifToolPath 'exiftool.exe' } |
                Should -Throw 'ExifTool could not read date metadata*read failed'
    }

    It 'throws when ExifTool returns invalid JSON' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{ ExitCode = 0; StdOut = 'not-json'; StdErr = '' }
        }

        { Get-MediaDateTag -Path 'clip.mov' -ExifToolPath 'exiftool.exe' } |
                Should -Throw 'ExifTool returned invalid date metadata*'
    }

    It 'throws when ExifTool returns more than one record' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{ ExitCode = 0; StdOut = '[{},{}]'; StdErr = '' }
        }

        { Get-MediaDateTag -Path 'clip.mov' -ExifToolPath 'exiftool.exe' } |
                Should -Throw 'ExifTool returned an unexpected number*'
    }
}
