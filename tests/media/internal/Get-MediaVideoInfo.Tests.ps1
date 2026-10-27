# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for media\internal\Get-MediaVideoInfo.ps1.

.DESCRIPTION
    Mocks FFprobe results to verify codec and bitrate extraction and explicit
    error handling.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\ConvertTo-QuotedArgument.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Invoke-MediaTool.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Get-MediaVideoInfo.ps1')
}

Describe 'Get-MediaVideoInfo' {
    It 'returns the canonical codec name and stream bitrate' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{
                ExitCode = 0
                StdOut = '{"streams":[{"codec_name":"H264","bit_rate":"16992002"}],"format":{"bit_rate":"17251064"}}'
                StdErr = ''
            }
        }

        $result = Get-MediaVideoInfo -Path 'C:\Videos\clip.mp4' -FFprobePath 'C:\Tools\ffprobe.exe'
        $result.Codec | Should -Be 'h264'
        $result.Bitrate | Should -Be 16992002
        Should -Invoke Invoke-MediaTool -Times 1 -ParameterFilter {
            $ExecutablePath -eq 'C:\Tools\ffprobe.exe' -and
                    $Arguments -contains '-select_streams' -and $Arguments -contains 'v:0'
        }
    }

    It 'uses the format bitrate when the stream bitrate is unavailable' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{
                ExitCode = 0
                StdOut = '{"streams":[{"codec_name":"h264","bit_rate":"N/A"}],"format":{"bit_rate":"11500000"}}'
                StdErr = ''
            }
        }

        $result = Get-MediaVideoInfo -Path 'clip.mp4' -FFprobePath 'ffprobe.exe'
        $result.Bitrate | Should -Be 11500000
    }

    It 'returns an unknown bitrate when neither stream nor format bitrate is available' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{
                ExitCode = 0
                StdOut = '{"streams":[{"codec_name":"h264","bit_rate":"N/A"}],"format":{"bit_rate":"N/A"}}'
                StdErr = ''
            }
        }

        $result = Get-MediaVideoInfo -Path 'clip.mp4' -FFprobePath 'ffprobe.exe'
        $result.Bitrate | Should -BeNullOrEmpty
    }

    It 'throws when FFprobe exits unsuccessfully' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'probe failed' }
        }

        { Get-MediaVideoInfo -Path 'clip.mp4' -FFprobePath 'ffprobe.exe' } |
                Should -Throw 'FFprobe failed*probe failed'
    }

    It 'throws when no video stream is returned' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{ ExitCode = 0; StdOut = '{"streams":[],"format":{}}'; StdErr = '' }
        }

        { Get-MediaVideoInfo -Path 'clip.mp4' -FFprobePath 'ffprobe.exe' } |
                Should -Throw 'FFprobe did not return exactly one video stream*'
    }
}
