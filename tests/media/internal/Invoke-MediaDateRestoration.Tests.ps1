# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>
<#
.SYNOPSIS
    Unit tests for media\internal\Invoke-MediaDateRestoration.ps1.

.DESCRIPTION
    Verifies file renaming, supported filesystem dates, and metadata arguments.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\ConvertTo-QuotedArgument.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Invoke-MediaTool.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Get-MediaDateUpdateArgument.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\Invoke-MediaDateRestoration.ps1')
}

Describe 'Invoke-MediaDateRestoration' {
    It 'renames the file, sets filesystem dates, and writes the legacy date tags' {
        Mock Invoke-MediaTool {
            if ($Arguments -contains '-j')
            {
                return [pscustomobject]@{ ExitCode = 0; StdOut = '{}'; StdErr = '' }
            }
            [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
        }
        $sourcePath = Join-Path $TestDrive 'source.mov'
        $targetPath = Join-Path $TestDrive '21-06-07 08-09-10 ABCD.mov'
        $null = New-Item -ItemType File -Path $sourcePath
        $source = Get-Item -LiteralPath $sourcePath
        $date = [datetime]'2021-06-07T08:09:10'

        $result = Invoke-MediaDateRestoration -File $source -TargetPath $targetPath `
            -DateTime $date -ExifToolPath 'exiftool.exe'

        $result.FilePath | Should -Be $targetPath
        Test-Path -LiteralPath $sourcePath | Should -BeFalse
        [System.IO.File]::GetCreationTime($targetPath) | Should -Be $date
        [System.IO.File]::GetLastWriteTime($targetPath) | Should -Be $date
        Should -Invoke Invoke-MediaTool -Times 1 -ParameterFilter {
            $Arguments -contains '-DateTimeOriginal=2021-06-07 08:09:10' -and
                    $Arguments -contains '-TrackModifyDate=2021-06-07 08:09:10' -and
                    $Arguments[-1] -eq $targetPath
        }
    }

    It 'does not rename a file when the target path is already its current path' {
        Mock Invoke-MediaTool {
            [pscustomobject]@{
                ExitCode = 0
                StdOut = '[{"EXIF:DateTimeOriginal":"2021-06-07 08:09:10","EXIF:CreateDate":"2021-06-07 08:09:10","EXIF:ModifyDate":"2021-06-07 08:09:10","QuickTime:MediaCreateDate":"2021-06-07 08:09:10","QuickTime:MediaModifyDate":"2021-06-07 08:09:10","QuickTime:TrackCreateDate":"2021-06-07 08:09:10","QuickTime:TrackModifyDate":"2021-06-07 08:09:10"}]'
                StdErr = ''
            }
        }
        $folder = Join-Path $TestDrive 'already-formatted'
        $null = New-Item -ItemType Directory -Path $folder
        $sourcePath = Join-Path $folder '21-06-07 08-09-10 ABCD.mov'
        $null = New-Item -ItemType File -Path $sourcePath
        $source = Get-Item -LiteralPath $sourcePath

        [System.IO.File]::SetCreationTime($sourcePath, [datetime]'2021-06-07T08:09:10')
        [System.IO.File]::SetLastWriteTime($sourcePath, [datetime]'2021-06-07T08:09:10')
        $result = Invoke-MediaDateRestoration -File $source -TargetPath $sourcePath `
            -DateTime ([datetime]'2021-06-07T08:09:10') -ExifToolPath 'exiftool.exe'

        $result.FilePath | Should -Be $sourcePath
        Test-Path -LiteralPath $sourcePath | Should -BeTrue
        @(Get-ChildItem -LiteralPath $folder -File).Count | Should -Be 1
        [System.IO.File]::GetCreationTime($sourcePath) | Should -Be ([datetime]'2021-06-07T08:09:10')
        [System.IO.File]::GetLastWriteTime($sourcePath) | Should -Be ([datetime]'2021-06-07T08:09:10')
        Should -Invoke Invoke-MediaTool -Times 1 -ParameterFilter { $Arguments -contains '-j' }
    }
}
