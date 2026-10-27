# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for media\internal\Test-MediaVideoCodecEfficient.ps1.

.DESCRIPTION
    Verifies which video codecs the media optimizer skips.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Test-MediaVideoCodecEfficient.ps1')
}

Describe 'Test-MediaVideoCodecEfficient' {
    It 'skips H.264 at or below 1.9 Mb/s and skips HEVC, AV1, and VP9' {
        foreach ($codec in @('h264', 'H264'))
        {
            Test-MediaVideoCodecEfficient -Codec $codec -VideoBitrate 1900000 | Should -BeTrue
            Test-MediaVideoCodecEfficient -Codec $codec -VideoBitrate 1900001 | Should -BeFalse
            Test-MediaVideoCodecEfficient -Codec $codec -VideoBitrate 0 | Should -BeTrue
        }
        foreach ($codec in @('hevc', 'av1', 'vp9'))
        {
            Test-MediaVideoCodecEfficient -Codec $codec -VideoBitrate 20000000 | Should -BeTrue
        }
    }

    It 're-encodes H.264 above 1.9 Mb/s and does not skip other codecs' {
        Test-MediaVideoCodecEfficient -Codec 'h264' -VideoBitrate 1900001 | Should -BeFalse
        Test-MediaVideoCodecEfficient -Codec 'h264' -VideoBitrate 12546276 -HasOriginalBackup $true | Should -BeTrue
        foreach ($codec in @('mpeg4', 'mpeg2video', 'prores', 'theora'))
        {
            Test-MediaVideoCodecEfficient -Codec $codec -VideoBitrate 20000000 | Should -BeFalse
        }
    }

    It 'trims whitespace around codec names' {
        Test-MediaVideoCodecEfficient -Codec ' hevc ' -VideoBitrate 1000000 | Should -BeTrue
        Test-MediaVideoCodecEfficient -Codec ' mpeg4 ' -VideoBitrate 1000000 | Should -BeFalse
    }
}
