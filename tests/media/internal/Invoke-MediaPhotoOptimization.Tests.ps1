# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig
# - Copilot
<#
.SYNOPSIS
    Unit tests for media\internal\Invoke-MediaPhotoOptimization.ps1.

.DESCRIPTION
    Mocks FFmpeg, FFprobe, and ExifTool results while using representative
    JPEG files under TestDrive to exercise safe photo optimization and replacement.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Invoke-MediaTool.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Get-MediaDateTag.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Set-MediaFileTimestamp.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Get-MediaPhotoOptimizationPlan.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Invoke-MediaPhotoOptimization.ps1')
    $script:ExifToolConfigPath = [System.IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot '..\..\..\media\internal\exiftool.config')
    )
}

Describe 'Invoke-MediaPhotoOptimization' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ('photo-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Folder -Force | Out-Null
        $script:PhotoPath = Join-Path $script:Folder 'sample.jpg'
        [System.IO.File]::WriteAllBytes($script:PhotoPath,[byte[]]::new(100))
        $script:Metadata = @{ 'EXIF:DateTimeOriginal' = '"2021:05:06 12:00:00"' }

        Mock Get-MediaDateTag { $script:Metadata }
        Mock Invoke-MediaTool {
            if ($Arguments -contains '-s3')
            {
                $marker = if ( $Arguments[-1].EndsWith('.part'))
                {
                    'Optimize-MediaSize/photo-v1'
                }
                else
                {
                    ''
                }
                [pscustomobject]@{ ExitCode = 0; StdOut = $marker; StdErr = '' }
                return
            }
            if ($Arguments -contains '-show_entries')
            {
                [pscustomobject]@{
                    ExitCode = 0
                    StdOut = '{"streams":[{"width":6000,"height":4000}]}'
                    StdErr = ''
                }
                return
            }
            if ($Arguments -contains '-c:v')
            {
                [System.IO.File]::WriteAllBytes($Arguments[-1],[byte[]]::new(10))
            }
            [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }
    }

    It 'writes a smaller JPEG, backs up the source, and preserves timestamps' {
        $timestamp = [datetime]::SpecifyKind([datetime]::new(2021, 5, 6, 12, 30, 0), [System.DateTimeKind]::Utc)
        Set-MediaFileTimestamp -Path $script:PhotoPath -CreationTimeUtc $timestamp `
            -LastWriteTimeUtc $timestamp -LastAccessTimeUtc $timestamp
        $sourceTimes = Get-Item -LiteralPath $script:PhotoPath
        $expectedCreation = $sourceTimes.CreationTimeUtc
        $expectedWrite = $sourceTimes.LastWriteTimeUtc
        $expectedAccess = $sourceTimes.LastAccessTimeUtc

        $result = Invoke-MediaPhotoOptimization -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFmpegPath 'ffmpeg.exe' -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath `
            -ReplaceOriginal $false -TargetSizeBytes 50 -EstimatedOutputSizeBytes 25

        $result.Success | Should -BeTrue
        $result.ResultBytes | Should -Be 10
        (Test-Path -LiteralPath $script:PhotoPath) | Should -BeTrue
        $output = Get-Item -LiteralPath $script:PhotoPath
        $output.CreationTimeUtc | Should -Be $expectedCreation
        $output.LastWriteTimeUtc | Should -Be $expectedWrite
        $output.LastAccessTimeUtc | Should -Be $expectedAccess
        (Get-Item -LiteralPath (Join-Path $script:Folder 'sample_orig.jpg')).Length | Should -Be 100
        (Get-ChildItem -LiteralPath $script:Folder -Force -Filter '.optimize-*.jpg.part') |
                Should -BeNullOrEmpty
        (Get-ChildItem -LiteralPath $script:Folder -Force -Filter '.optimize-source-*.part') |
                Should -BeNullOrEmpty

        Should -Invoke Invoke-MediaTool -Times 1 -Exactly -ParameterFilter {
            $codecIndex = [array]::IndexOf($Arguments, '-c:v')
            $qualityIndex = [array]::IndexOf($Arguments, '-q:v')
            $filterIndex = [array]::IndexOf($Arguments, '-vf')
            $formatIndex = [array]::IndexOf($Arguments, '-f')
            $codecIndex -ge 0 -and $Arguments[$codecIndex + 1] -eq 'mjpeg' -and
                    $qualityIndex -ge 0 -and $Arguments[$qualityIndex + 1] -eq '2' -and
                    $filterIndex -ge 0 -and $Arguments[$filterIndex + 1] -eq 'scale=3000:2000:force_original_aspect_ratio=decrease:force_divisible_by=2' -and
                    $Arguments -contains '-noautorotate' -and
                    $Arguments -contains 'yuvj420p' -and
                    $formatIndex -ge 0 -and $Arguments[$formatIndex + 1] -eq 'image2' -and
                    $Arguments[-1].EndsWith('.jpg.part')
        }
        Should -Invoke Invoke-MediaTool -Times 1 -Exactly -ParameterFilter {
            $ExecutablePath -eq 'exiftool.exe' -and
                    $Arguments -contains '-config' -and
                    $Arguments -contains '-XMP-psscriptbox:OptimizationProfile=Optimize-MediaSize/photo-v1' -and
                    $Arguments[-1].EndsWith('.jpg.part')
        }
    }

    It 'targets an estimated 5 MB output by default' {
        $stream = [System.IO.File]::Open($script:PhotoPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
        try
        {
            $stream.SetLength(7MB)
        }
        finally
        {
            $stream.Dispose()
        }
        Mock Invoke-MediaTool {
            if ($Arguments -contains '-s3')
            {
                $marker = if ( $Arguments[-1].EndsWith('.part'))
                {
                    'Optimize-MediaSize/photo-v1'
                }
                else
                {
                    ''
                }
                [pscustomobject]@{ ExitCode = 0; StdOut = $marker; StdErr = '' }
                return
            }
            if ($Arguments -contains '-show_entries')
            {
                [pscustomobject]@{
                    ExitCode = 0
                    StdOut = '{"streams":[{"width":6000,"height":4800}]}'
                    StdErr = ''
                }
                return
            }
            if ($Arguments -contains '-c:v')
            {
                [System.IO.File]::WriteAllBytes($Arguments[-1],[byte[]]::new(10))
            }
            [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }

        $result = Invoke-MediaPhotoOptimization -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFmpegPath 'ffmpeg.exe' -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath `
            -ReplaceOriginal $false

        $result.Success | Should -BeTrue
        Should -Invoke Invoke-MediaTool -Times 1 -Exactly -ParameterFilter {
            $filterIndex = [array]::IndexOf($Arguments, '-vf')
            $filterIndex -ge 0 -and
                    $Arguments[$filterIndex + 1] -eq 'scale=5070:4056:force_original_aspect_ratio=decrease:force_divisible_by=2'
        }
    }

    It 'recompresses a high-density photo without changing its pixel dimensions' {
        $stream = [System.IO.File]::Open($script:PhotoPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
        try
        {
            $stream.SetLength(4MB)
        }
        finally
        {
            $stream.Dispose()
        }
        Mock Invoke-MediaTool {
            if ($Arguments -contains '-s3')
            {
                $marker = if ( $Arguments[-1].EndsWith('.part'))
                {
                    'Optimize-MediaSize/photo-v1'
                }
                else
                {
                    ''
                }
                [pscustomobject]@{ ExitCode = 0; StdOut = $marker; StdErr = '' }
                return
            }
            if ($Arguments -contains '-show_entries')
            {
                [pscustomobject]@{
                    ExitCode = 0
                    StdOut = '{"streams":[{"width":2000,"height":1000}]}'
                    StdErr = ''
                }
                return
            }
            if ($Arguments -contains '-c:v')
            {
                [System.IO.File]::WriteAllBytes($Arguments[-1],[byte[]]::new(10))
            }
            [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }

        $result = Invoke-MediaPhotoOptimization -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFmpegPath 'ffmpeg.exe' -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath `
            -ReplaceOriginal $false

        $result.Success | Should -BeTrue
        Should -Invoke Invoke-MediaTool -Times 1 -Exactly -ParameterFilter {
            $codecIndex = [array]::IndexOf($Arguments, '-c:v')
            $filterIndex = [array]::IndexOf($Arguments, '-vf')
            $codecIndex -ge 0 -and $Arguments[$codecIndex + 1] -eq 'mjpeg' -and $filterIndex -eq -1
        }
    }

    It 'replaces a JPEG without retaining a backup when ReplaceOriginal is enabled' {
        $result = Invoke-MediaPhotoOptimization -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFmpegPath 'ffmpeg.exe' -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath `
            -ReplaceOriginal $true -TargetSizeBytes 50 -EstimatedOutputSizeBytes 25

        $result.Success | Should -BeTrue
        (Get-Item -LiteralPath $script:PhotoPath).Length | Should -Be 10
        (Test-Path -LiteralPath (Join-Path $script:Folder 'sample_orig.jpg')) | Should -BeFalse
        (Get-ChildItem -LiteralPath $script:Folder -Force -Filter '.optimize-source-*.part') |
                Should -BeNullOrEmpty
    }

    It 'skips photos below both thresholds without encoding them' {
        $result = Invoke-MediaPhotoOptimization -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFmpegPath 'ffmpeg.exe' -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath `
            -ReplaceOriginal $false

        $result.Skipped | Should -BeTrue
        $result.FailureReason | Should -Match 'at or below'
        (Get-Item -LiteralPath $script:PhotoPath).Length | Should -Be 100
        Should -Invoke Invoke-MediaTool -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains '-show_entries'
        }
        Should -Invoke Invoke-MediaTool -Times 0 -Exactly -ParameterFilter {
            $Arguments -contains '-c:v'
        }
        Should -Invoke Invoke-MediaTool -Times 0 -Exactly -ParameterFilter {
            $Arguments -contains '-XMP-psscriptbox:OptimizationProfile=Optimize-MediaSize/photo-v1'
        }
    }

    It 'leaves the source unchanged when FFprobe cannot read photo dimensions' {
        Mock Invoke-MediaTool {
            if ($Arguments -contains '-show_entries')
            {
                [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'probe failed' }
            }
            else
            {
                [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
            }
        }

        $result = Invoke-MediaPhotoOptimization -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFmpegPath 'ffmpeg.exe' -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath `
            -ReplaceOriginal $false -TargetSizeBytes 50 -EstimatedOutputSizeBytes 25

        $result.Success | Should -BeFalse
        $result.FailureReason | Should -Match 'FFprobe failed to read JPEG dimensions'
        (Get-Item -LiteralPath $script:PhotoPath).Length | Should -Be 100
        (Test-Path -LiteralPath (Join-Path $script:Folder 'sample_orig.jpg')) | Should -BeFalse
    }

    It 'leaves the source unchanged when date metadata differs' {
        Mock Get-MediaDateTag {
            if ($Path -eq $script:PhotoPath)
            {
                return @{ 'EXIF:DateTimeOriginal' = '"2021:05:06 12:00:00"' }
            }
            return @{ 'EXIF:DateTimeOriginal' = '"2026:10:27 09:00:00"' }
        }
        $before = [System.IO.File]::ReadAllBytes($script:PhotoPath)

        $result = Invoke-MediaPhotoOptimization -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFmpegPath 'ffmpeg.exe' -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath `
            -ReplaceOriginal $false -TargetSizeBytes 50 -EstimatedOutputSizeBytes 25

        $result.Success | Should -BeFalse
        $result.FailureReason | Should -Match 'Date metadata changed'
        [System.IO.File]::ReadAllBytes($script:PhotoPath) | Should -Be $before
        (Test-Path -LiteralPath (Join-Path $script:Folder 'sample_orig.jpg')) | Should -BeFalse
        Should -Invoke Invoke-MediaTool -Times 0 -Exactly -ParameterFilter {
            $Arguments -contains '-XMP-psscriptbox:OptimizationProfile=Optimize-MediaSize/photo-v1'
        }
    }

    It 'skips a result that is not smaller and leaves the source in place' {
        Mock Invoke-MediaTool {
            if ($Arguments -contains '-s3')
            {
                $marker = if ( $Arguments[-1].EndsWith('.part'))
                {
                    'Optimize-MediaSize/photo-v1'
                }
                else
                {
                    ''
                }
                [pscustomobject]@{ ExitCode = 0; StdOut = $marker; StdErr = '' }
                return
            }
            if ($Arguments -contains '-show_entries')
            {
                [pscustomobject]@{
                    ExitCode = 0
                    StdOut = '{"streams":[{"width":6000,"height":4000}]}'
                    StdErr = ''
                }
                return
            }
            if ($Arguments -contains '-c:v')
            {
                [System.IO.File]::WriteAllBytes($Arguments[-1],[byte[]]::new(100))
            }
            [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }

        $result = Invoke-MediaPhotoOptimization -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFmpegPath 'ffmpeg.exe' -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath `
            -ReplaceOriginal $false -TargetSizeBytes 50 -EstimatedOutputSizeBytes 25

        $result.Skipped | Should -BeTrue
        $result.FailureReason | Should -Be 'No size reduction'
        (Test-Path -LiteralPath $script:PhotoPath) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $script:Folder 'sample_orig.jpg')) | Should -BeFalse
        Should -Invoke Invoke-MediaTool -Times 0 -Exactly -ParameterFilter {
            $Arguments -contains '-XMP-psscriptbox:OptimizationProfile=Optimize-MediaSize/photo-v1'
        }
    }

    It 'does not overwrite an existing original backup' {
        $backupPath = Join-Path $script:Folder 'sample_orig.jpg'
        [System.IO.File]::WriteAllText($backupPath, 'existing backup')

        $result = Invoke-MediaPhotoOptimization -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFmpegPath 'ffmpeg.exe' -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath `
            -ReplaceOriginal $false -TargetSizeBytes 50 -EstimatedOutputSizeBytes 25

        $result.Success | Should -BeFalse
        $result.FailureReason | Should -Match 'Original backup already exists'
        (Get-Item -LiteralPath $script:PhotoPath).Length | Should -Be 100
        [System.IO.File]::ReadAllText($backupPath) | Should -Be 'existing backup'
        Should -Invoke Invoke-MediaTool -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains '-show_entries'
        }
        Should -Invoke Invoke-MediaTool -Times 0 -Exactly -ParameterFilter {
            $Arguments -contains '-c:v'
        }
    }

    It 'leaves the source unchanged when FFmpeg fails' {
        Mock Invoke-MediaTool {
            if ($Arguments -contains '-show_entries')
            {
                [pscustomobject]@{
                    ExitCode = 0
                    StdOut = '{"streams":[{"width":6000,"height":4000}]}'
                    StdErr = ''
                }
            }
            elseif ($Arguments -contains '-c:v')
            {
                [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'encoding error' }
            }
            else
            {
                [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
            }
        }

        $result = Invoke-MediaPhotoOptimization -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFmpegPath 'ffmpeg.exe' -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath `
            -ReplaceOriginal $false -TargetSizeBytes 50 -EstimatedOutputSizeBytes 25

        $result.Success | Should -BeFalse
        $result.FailureReason | Should -Match 'FFmpeg failed'
        (Test-Path -LiteralPath $script:PhotoPath) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $script:Folder 'sample_orig.jpg')) | Should -BeFalse
    }

    It 'leaves the source unchanged when ExifTool cannot copy metadata' {
        Mock Invoke-MediaTool {
            if ($Arguments -contains '-show_entries')
            {
                [pscustomobject]@{
                    ExitCode = 0
                    StdOut = '{"streams":[{"width":6000,"height":4000}]}'
                    StdErr = ''
                }
            }
            elseif ($Arguments -contains '-TagsFromFile')
            {
                [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'copy failed' }
            }
            elseif ($Arguments -contains '-c:v')
            {
                [System.IO.File]::WriteAllBytes($Arguments[-1],[byte[]]::new(10))
                [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
            }
            else
            {
                [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
            }
        }

        $result = Invoke-MediaPhotoOptimization -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFmpegPath 'ffmpeg.exe' -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath `
            -ReplaceOriginal $false -TargetSizeBytes 50 -EstimatedOutputSizeBytes 25

        $result.Success | Should -BeFalse
        $result.FailureReason | Should -Match 'ExifTool could not copy metadata'
        (Test-Path -LiteralPath $script:PhotoPath) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $script:Folder 'sample_orig.jpg')) | Should -BeFalse
    }
}
