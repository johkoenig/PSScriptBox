<#
.SYNOPSIS
    Unit tests for media\internal\Get-MediaPhotoOptimizationPlan.ps1.

.DESCRIPTION
    Tests JPEG dimension probing and density-first optimization eligibility.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Copilot

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Invoke-MediaTool.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Get-MediaPhotoOptimizationPlan.ps1')
    $script:ExifToolConfigPath = [System.IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot '..\..\..\media\internal\exiftool.config')
    )
}

Describe 'Get-MediaPhotoOptimizationPlan' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ('photo-plan-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Folder -Force | Out-Null
        $script:PhotoPath = Join-Path $script:Folder 'sample.jpg'
        [System.IO.File]::WriteAllBytes($script:PhotoPath,[byte[]]::new(1))

        Mock Invoke-MediaTool {
            if ($ExecutablePath -eq 'exiftool.exe')
            {
                [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
                return
            }
            [pscustomobject]@{
                ExitCode = 0
                StdOut = '{"streams":[{"width":2000,"height":1000}]}'
                StdErr = ''
            }
        }
    }

    It 'selects density recompression before the size-based resize rule' {
        $stream = [System.IO.File]::Open($script:PhotoPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
        try
        {
            $stream.SetLength(7MB)
        }
        finally
        {
            $stream.Dispose()
        }

        $plan = Get-MediaPhotoOptimizationPlan -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath

        $plan.OptimizationMode | Should -Be 'Density'
        $plan.ShouldOptimize | Should -BeTrue
        $plan.Width | Should -Be 2000
        $plan.Height | Should -Be 1000
        $plan.MegabytesPerMegapixel | Should -BeGreaterThan 0.25
    }

    It 'selects resizing when size is over 6 MB but density is not over the density threshold' {
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
            if ($ExecutablePath -eq 'exiftool.exe')
            {
                [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
                return
            }
            [pscustomobject]@{
                ExitCode = 0
                StdOut = '{"streams":[{"width":6000,"height":5000}]}'
                StdErr = ''
            }
        }

        $plan = Get-MediaPhotoOptimizationPlan -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath

        $plan.OptimizationMode | Should -Be 'Size'
        $plan.ShouldOptimize | Should -BeTrue
        $plan.MegabytesPerMegapixel | Should -BeLessThan 0.25
    }

    It 'skips a small photo when its density is also at or below the threshold' {
        $plan = Get-MediaPhotoOptimizationPlan -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath

        $plan.ShouldOptimize | Should -BeFalse
        $plan.OptimizationMode | Should -BeNullOrEmpty
        $plan.SkipReason | Should -Match 'at or below'
    }

    It 'fails when FFprobe cannot read the photo dimensions' {
        Mock Invoke-MediaTool {
            if ($ExecutablePath -eq 'exiftool.exe')
            {
                [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
                return
            }
            [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'probe failed' }
        }

        {
            Get-MediaPhotoOptimizationPlan -Photo (Get-Item -LiteralPath $script:PhotoPath) `
                -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
                -ExifToolConfigPath $script:ExifToolConfigPath
        } | Should -Throw '*FFprobe failed to read JPEG dimensions*'
    }

    It 'skips a file with the PSScriptBox optimization marker before probing dimensions' {
        Mock Invoke-MediaTool {
            if ($ExecutablePath -eq 'exiftool.exe')
            {
                [pscustomobject]@{
                    ExitCode = 0
                    StdOut = 'Optimize-MediaSize/photo-v1'
                    StdErr = ''
                }
                return
            }
            throw 'FFprobe should not be called for a marked file.'
        }

        $plan = Get-MediaPhotoOptimizationPlan -Photo (Get-Item -LiteralPath $script:PhotoPath) `
            -FFprobePath 'ffprobe.exe' -ExifToolPath 'exiftool.exe' `
            -ExifToolConfigPath $script:ExifToolConfigPath

        $plan.ProcessedByScript | Should -BeTrue
        $plan.ShouldOptimize | Should -BeFalse
        $plan.SkipReason | Should -Match 'already optimized'
        Should -Invoke Invoke-MediaTool -Times 0 -Exactly -ParameterFilter {
            $ExecutablePath -eq 'ffprobe.exe'
        }
    }
}
