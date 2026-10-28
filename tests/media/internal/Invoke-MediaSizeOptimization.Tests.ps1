# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for media\internal\Invoke-MediaSizeOptimization.ps1.

.DESCRIPTION
    Mocks FFmpeg, ExifTool metadata, and the compressor process while using
    representative files under TestDrive to exercise safe replacement behavior.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Invoke-MediaTool.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Get-MediaDateMetadata.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Set-MediaFileTimestamps.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Invoke-MediaSizeOptimization.ps1')
}

Describe 'Invoke-MediaSizeOptimization' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ('video-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Folder -Force | Out-Null
        $script:VideoPath = Join-Path $script:Folder 'clip.mov'
        [System.IO.File]::WriteAllBytes($script:VideoPath,[byte[]]::new(100))
        $script:Metadata = @{ 'QuickTime:CreateDate' = '"2021:05:06 12:00:00"' }

        Mock Get-MediaDateMetadata { $script:Metadata }
        Mock Invoke-MediaTool {
            if ($Arguments -contains '-c:v')
            {
                [System.IO.File]::WriteAllBytes($Arguments[-1],[byte[]]::new(10))
            }
            [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }
    }

    It 'backs up the source and writes a smaller MP4 with preserved timestamps' {
        $timestamp = [datetime]::SpecifyKind([datetime]::new(2021, 5, 6, 12, 30, 0), [System.DateTimeKind]::Utc)
        Set-MediaFileTimestamps -Path $script:VideoPath -CreationTimeUtc $timestamp `
            -LastWriteTimeUtc $timestamp -LastAccessTimeUtc $timestamp
        $sourceTimes = Get-Item -LiteralPath $script:VideoPath
        $expectedCreation = $sourceTimes.CreationTimeUtc
        $expectedWrite = $sourceTimes.LastWriteTimeUtc
        $expectedAccess = $sourceTimes.LastAccessTimeUtc

        $result = Invoke-MediaSizeOptimization -Video (Get-Item -LiteralPath $script:VideoPath) `
            -FFmpegPath 'ffmpeg.exe' -ExifToolPath 'exiftool.exe' -ReplaceOriginal $false

        $result.Success | Should -BeTrue
        $result.ResultBytes | Should -Be 10
        (Test-Path -LiteralPath $script:VideoPath) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $script:Folder 'clip_orig.mov')) | Should -BeTrue
        $output = Get-Item -LiteralPath (Join-Path $script:Folder 'clip.mp4')
        $output.CreationTimeUtc | Should -Be $expectedCreation
        $output.LastWriteTimeUtc | Should -Be $expectedWrite
        $output.LastAccessTimeUtc | Should -Be $expectedAccess
        (Get-ChildItem -LiteralPath $script:Folder -Force | Where-Object { $_.Name -like '.optimize-*.mp4.part' }) |
                Should -BeNullOrEmpty
    }

    It 'removes the source only when ReplaceOriginal is enabled' {
        $result = Invoke-MediaSizeOptimization -Video (Get-Item -LiteralPath $script:VideoPath) `
            -FFmpegPath 'ffmpeg.exe' -ExifToolPath 'exiftool.exe' -ReplaceOriginal $true

        $result.Success | Should -BeTrue
        (Test-Path -LiteralPath $script:VideoPath) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $script:Folder 'clip_orig.mov')) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $script:Folder 'clip.mp4')) | Should -BeTrue
    }

    It 'backs up an MP4 source before replacing it with the optimized output' {
        $mp4Path = Join-Path $script:Folder 'source.mp4'
        [System.IO.File]::WriteAllBytes($mp4Path,[byte[]]::new(100))
        $timestamp = [datetime]::SpecifyKind([datetime]::new(2021, 5, 6, 12, 30, 0), [System.DateTimeKind]::Utc)
        Set-MediaFileTimestamps -Path $mp4Path -CreationTimeUtc $timestamp `
            -LastWriteTimeUtc $timestamp -LastAccessTimeUtc $timestamp
        $sourceTimes = Get-Item -LiteralPath $mp4Path
        $expectedCreation = $sourceTimes.CreationTimeUtc
        $expectedWrite = $sourceTimes.LastWriteTimeUtc
        $expectedAccess = $sourceTimes.LastAccessTimeUtc

        $result = Invoke-MediaSizeOptimization -Video (Get-Item -LiteralPath $mp4Path) `
            -FFmpegPath 'ffmpeg.exe' -ExifToolPath 'exiftool.exe' -ReplaceOriginal $false `
            -VideoBitrateKbps 1900

        $result.Success | Should -BeTrue
        Should -Invoke Invoke-MediaTool -Times 1 -Exactly -ParameterFilter {
            $codecIndex = [array]::IndexOf($Arguments, '-c:v')
            $bitrateIndex = [array]::IndexOf($Arguments, '-b:v')
            $filterIndex = [array]::IndexOf($Arguments, '-vf')
            $formatIndex = [array]::IndexOf($Arguments, '-f')
            $tagIndex = [array]::IndexOf($Arguments, '-tag:v')
            $codecIndex -ge 0 -and $Arguments[$codecIndex + 1] -eq 'libx265' -and
                    $bitrateIndex -ge 0 -and $Arguments[$bitrateIndex + 1] -eq '1900k' -and
                    $filterIndex -ge 0 -and $Arguments[$filterIndex + 1] -eq "scale=w='if(gte(iw,ih),min(1280,iw),-2)':h='if(gte(iw,ih),-2,min(1280,ih))'" -and
                    $tagIndex -ge 0 -and $Arguments[$tagIndex + 1] -eq 'hvc1' -and
                    $formatIndex -ge 0 -and $Arguments[$formatIndex + 1] -eq 'mp4' -and
                    $Arguments[-1].EndsWith('.part')
        }
        $output = Get-Item -LiteralPath $mp4Path
        $output.Length | Should -Be 10
        $output.CreationTimeUtc | Should -Be $expectedCreation
        $output.LastWriteTimeUtc | Should -Be $expectedWrite
        $output.LastAccessTimeUtc | Should -Be $expectedAccess
        (Test-Path -LiteralPath (Join-Path $script:Folder 'source_orig.mp4')) | Should -BeTrue
        (Get-Item -LiteralPath (Join-Path $script:Folder 'source_orig.mp4')).Length | Should -Be 100
        (Get-ChildItem -LiteralPath $script:Folder -Force -Filter '.optimize-source-*') |
                Should -BeNullOrEmpty
    }

    It 'restores timestamps captured before source probing' {
        $timestamp = [datetime]::SpecifyKind([datetime]::new(2021, 5, 6, 12, 30, 0), [System.DateTimeKind]::Utc)
        $laterAccess = $timestamp.AddDays(10)
        Set-MediaFileTimestamps -Path $script:VideoPath -CreationTimeUtc $timestamp `
            -LastWriteTimeUtc $timestamp -LastAccessTimeUtc $laterAccess
        $sourceTimestamps = @{
            CreationTimeUtc = $timestamp
            LastWriteTimeUtc = $timestamp
            LastAccessTimeUtc = $timestamp
        }

        $result = Invoke-MediaSizeOptimization -Video (Get-Item -LiteralPath $script:VideoPath) `
            -FFmpegPath 'ffmpeg.exe' -ExifToolPath 'exiftool.exe' -ReplaceOriginal $false `
            -OriginalTimestamps $sourceTimestamps

        $result.Success | Should -BeTrue
        $output = Get-Item -LiteralPath (Join-Path $script:Folder 'clip.mp4')
        $output.CreationTimeUtc | Should -Be $timestamp
        $output.LastWriteTimeUtc | Should -Be $timestamp
        $output.LastAccessTimeUtc | Should -Be $timestamp
    }

    It 'replaces an MP4 in place without retaining a backup when ReplaceOriginal is enabled' {
        $mp4Path = Join-Path $script:Folder 'source.mp4'
        [System.IO.File]::WriteAllBytes($mp4Path,[byte[]]::new(100))
        $result = Invoke-MediaSizeOptimization -Video (Get-Item -LiteralPath $mp4Path) `
            -FFmpegPath 'ffmpeg.exe' -ExifToolPath 'exiftool.exe' -ReplaceOriginal $true

        $result.Success | Should -BeTrue
        (Test-Path -LiteralPath $mp4Path) | Should -BeTrue
        (Get-Item -LiteralPath $mp4Path).Length | Should -Be 10
        (Test-Path -LiteralPath (Join-Path $script:Folder 'source_orig.mp4')) | Should -BeFalse
        (Get-ChildItem -LiteralPath $script:Folder -Force -Filter '.optimize-source-*') |
                Should -BeNullOrEmpty
    }

    It 'does not replace an MP4 if its original backup already exists' {
        $mp4Path = Join-Path $script:Folder 'source.mp4'
        [System.IO.File]::WriteAllBytes($mp4Path,[byte[]]::new(100))
        $backupPath = Join-Path $script:Folder 'source_orig.mp4'
        [System.IO.File]::WriteAllText($backupPath, 'existing backup')

        $result = Invoke-MediaSizeOptimization -Video (Get-Item -LiteralPath $mp4Path) `
            -FFmpegPath 'ffmpeg.exe' -ExifToolPath 'exiftool.exe' -ReplaceOriginal $false

        $result.Success | Should -BeFalse
        $result.FailureReason | Should -Match 'Original backup already exists'
        (Get-Item -LiteralPath $mp4Path).Length | Should -Be 100
        [System.IO.File]::ReadAllText($backupPath) | Should -Be 'existing backup'
        Should -Invoke Invoke-MediaTool -Times 0
    }

    It 'leaves the source unchanged when date metadata differs' {
        Mock Get-MediaDateMetadata {
            if ($Path -eq $script:VideoPath)
            {
                return @{ 'QuickTime:CreateDate' = '"2021:05:06 12:00:00"' }
            }
            return @{ 'QuickTime:CreateDate' = '"2026:10:27 09:00:00"' }
        }
        $before = [System.IO.File]::ReadAllBytes($script:VideoPath)

        $result = Invoke-MediaSizeOptimization -Video (Get-Item -LiteralPath $script:VideoPath) `
            -FFmpegPath 'ffmpeg.exe' -ExifToolPath 'exiftool.exe' -ReplaceOriginal $false

        $result.Success | Should -BeFalse
        $result.FailureReason | Should -Match 'Date metadata changed'
        (Test-Path -LiteralPath $script:VideoPath) | Should -BeTrue
        [System.IO.File]::ReadAllBytes($script:VideoPath) | Should -Be $before
        (Test-Path -LiteralPath (Join-Path $script:Folder 'clip.mp4')) | Should -BeFalse
    }

    It 'skips an MP4 that is not smaller and leaves the source in place' {
        Mock Invoke-MediaTool {
            if ($Arguments -contains '-c:v')
            {
                [System.IO.File]::WriteAllBytes($Arguments[-1],[byte[]]::new(100))
            }
            [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }

        $result = Invoke-MediaSizeOptimization -Video (Get-Item -LiteralPath $script:VideoPath) `
            -FFmpegPath 'ffmpeg.exe' -ExifToolPath 'exiftool.exe' -ReplaceOriginal $false

        $result.Skipped | Should -BeTrue
        $result.FailureReason | Should -Be 'No size reduction'
        (Test-Path -LiteralPath $script:VideoPath) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $script:Folder 'clip.mp4')) | Should -BeFalse
    }

    It 'does not overwrite an existing MP4 output' {
        $outputPath = Join-Path $script:Folder 'clip.mp4'
        [System.IO.File]::WriteAllText($outputPath, 'existing')

        $result = Invoke-MediaSizeOptimization -Video (Get-Item -LiteralPath $script:VideoPath) `
            -FFmpegPath 'ffmpeg.exe' -ExifToolPath 'exiftool.exe' -ReplaceOriginal $false

        $result.Success | Should -BeFalse
        $result.FailureReason | Should -Match 'Output already exists'
        [System.IO.File]::ReadAllText($outputPath) | Should -Be 'existing'
        Should -Invoke Invoke-MediaTool -Times 0
    }

    It 'does not replace a source when FFmpeg fails' {
        Mock Invoke-MediaTool {
            if ($Arguments -contains '-c:v')
            {
                [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'encoding error' }
            }
            else
            {
                [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
            }
        }

        $result = Invoke-MediaSizeOptimization -Video (Get-Item -LiteralPath $script:VideoPath) `
            -FFmpegPath 'ffmpeg.exe' -ExifToolPath 'exiftool.exe' -ReplaceOriginal $false

        $result.Success | Should -BeFalse
        $result.FailureReason | Should -Match 'FFmpeg failed'
        (Test-Path -LiteralPath $script:VideoPath) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $script:Folder 'clip_orig.mov')) | Should -BeFalse
    }
}
