# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for nextcloud\internal\Remove-EmptyMatchingDirectory.ps1.

.DESCRIPTION
    Verifies that only empty folders with an existing Nextcloud counterpart are
    deleted, deepest first. Links and junctions are never followed or deleted,
    and non-empty folders are kept. Failures are returned as objects instead of
    being written to the console. Uses TestDrive folders only.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\nextcloud\internal\Remove-EmptyMatchingDirectory.ps1')

    function New-Tree {
        param([string] $Root, [string[]] $Directory)
        foreach ($relative in $Directory) {
            New-Item -ItemType Directory -Path (Join-Path $Root $relative) -Force | Out-Null
        }
    }
}

Describe 'Remove-EmptyMatchingDirectory' {
    BeforeEach {
        $script:Local = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Cloud = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:Local, $script:Cloud -Force | Out-Null
    }

    It 'deletes an empty subfolder that exists in Nextcloud' {
        New-Tree -Root $script:Local -Directory 'empty'
        New-Tree -Root $script:Cloud -Directory 'empty'

        $result = Remove-EmptyMatchingDirectory -SourcePath $script:Local -DestinationPath $script:Cloud -RelativeDirectories @('empty')

        Test-Path -LiteralPath (Join-Path $script:Local 'empty') | Should -BeFalse
        $result.DeletedCount | Should -Be 1
        @($result.FailedDirectories).Count | Should -Be 0
    }

    It 'keeps an eligible folder when WhatIf is requested' {
        New-Tree -Root $script:Local -Directory 'empty'
        New-Tree -Root $script:Cloud -Directory 'empty'

        $result = Remove-EmptyMatchingDirectory -SourcePath $script:Local `
            -DestinationPath $script:Cloud -RelativeDirectories @('empty') -WhatIf

        Test-Path -LiteralPath (Join-Path $script:Local 'empty') | Should -BeTrue
        $result.DeletedCount | Should -Be 0
    }

    It 'keeps the main folder itself' {
        New-Tree -Root $script:Local -Directory 'empty'
        New-Tree -Root $script:Cloud -Directory 'empty'
        Remove-EmptyMatchingDirectory -SourcePath $script:Local -DestinationPath $script:Cloud -RelativeDirectories @('empty') | Out-Null
        Test-Path -LiteralPath $script:Local -PathType Container | Should -BeTrue
    }

    It 'keeps a subfolder that still contains a file' {
        New-Tree -Root $script:Local -Directory 'full'
        New-Tree -Root $script:Cloud -Directory 'full'
        [System.IO.File]::WriteAllText((Join-Path $script:Local 'full\keep.txt'), 'data')

        $result = Remove-EmptyMatchingDirectory -SourcePath $script:Local -DestinationPath $script:Cloud -RelativeDirectories @('full')

        Test-Path -LiteralPath (Join-Path $script:Local 'full\keep.txt') | Should -BeTrue
        $result.DeletedCount | Should -Be 0
    }

    It 'keeps an empty subfolder that has no Nextcloud counterpart' {
        New-Tree -Root $script:Local -Directory 'local-only'

        $result = Remove-EmptyMatchingDirectory -SourcePath $script:Local -DestinationPath $script:Cloud -RelativeDirectories @('local-only')

        Test-Path -LiteralPath (Join-Path $script:Local 'local-only') | Should -BeTrue
        $result.DeletedCount | Should -Be 0
    }

    It 'keeps an empty subfolder whose Nextcloud counterpart is only a file' {
        New-Tree -Root $script:Local -Directory 'name'
        [System.IO.File]::WriteAllText((Join-Path $script:Cloud 'name'), 'file')

        $result = Remove-EmptyMatchingDirectory -SourcePath $script:Local -DestinationPath $script:Cloud -RelativeDirectories @('name')

        Test-Path -LiteralPath (Join-Path $script:Local 'name') | Should -BeTrue
        $result.DeletedCount | Should -Be 0
    }

    It 'skips a listed folder that is missing in the source' {
        New-Tree -Root $script:Cloud -Directory 'gone'

        $result = Remove-EmptyMatchingDirectory -SourcePath $script:Local -DestinationPath $script:Cloud -RelativeDirectories @('gone')

        $result.DeletedCount | Should -Be 0
        @($result.FailedDirectories).Count | Should -Be 0
    }

    It 'removes nested empty folders deepest first' {
        New-Tree -Root $script:Local -Directory 'a\b'
        New-Tree -Root $script:Cloud -Directory 'a\b'

        $result = Remove-EmptyMatchingDirectory -SourcePath $script:Local -DestinationPath $script:Cloud -RelativeDirectories @('a', 'a\b')

        Test-Path -LiteralPath (Join-Path $script:Local 'a') | Should -BeFalse
        $result.DeletedCount | Should -Be 2
    }

    It 'does not follow or delete a junction in the source' {
        $target = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $target 'precious.txt'), 'keep')
        $junction = Join-Path $script:Local 'link'
        cmd /c mklink /J "$junction" "$target" | Out-Null
        if (-not (Test-Path -LiteralPath $junction)) { Set-ItResult -Skipped -Because 'junction could not be created'; return }
        New-Tree -Root $script:Cloud -Directory 'link'

        Remove-EmptyMatchingDirectory -SourcePath $script:Local -DestinationPath $script:Cloud -RelativeDirectories @('link') | Out-Null

        Test-Path -LiteralPath (Join-Path $target 'precious.txt') | Should -BeTrue
    }

    It 'does not delete an empty source folder whose Nextcloud counterpart is a junction' {
        $target = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        New-Tree -Root $script:Local -Directory 'link'
        $junction = Join-Path $script:Cloud 'link'
        cmd /c mklink /J "$junction" "$target" | Out-Null
        if (-not (Test-Path -LiteralPath $junction)) { Set-ItResult -Skipped -Because 'junction could not be created'; return }

        $result = Remove-EmptyMatchingDirectory -SourcePath $script:Local -DestinationPath $script:Cloud -RelativeDirectories @('link')

        Test-Path -LiteralPath (Join-Path $script:Local 'link') | Should -BeTrue
        $result.DeletedCount | Should -Be 0
    }

    It 'deletes nothing when the relative list is empty' {
        New-Tree -Root $script:Local -Directory 'empty'
        New-Tree -Root $script:Cloud -Directory 'empty'

        $result = Remove-EmptyMatchingDirectory -SourcePath $script:Local -DestinationPath $script:Cloud -RelativeDirectories @()

        Test-Path -LiteralPath (Join-Path $script:Local 'empty') | Should -BeTrue
        $result.DeletedCount | Should -Be 0
    }

    It 'collects a deletion failure as a failed-directory object and continues' {
        New-Tree -Root $script:Local -Directory 'locked'
        New-Tree -Root $script:Cloud -Directory 'locked'
        Mock Remove-Item { throw 'simulated lock' }

        $result = Remove-EmptyMatchingDirectory -SourcePath $script:Local -DestinationPath $script:Cloud -RelativeDirectories @('locked')

        $result.DeletedCount | Should -Be 0
        @($result.FailedDirectories).Count | Should -Be 1
        $result.FailedDirectories[0].RelativePath | Should -Be 'locked'
        $result.FailedDirectories[0].Message | Should -Match 'simulated lock'
    }
}
