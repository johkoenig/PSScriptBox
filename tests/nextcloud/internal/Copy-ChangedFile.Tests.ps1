# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for nextcloud\internal\Copy-ChangedFile.ps1.

.DESCRIPTION
    Checks identical-content skipping, duplicate detection within the source,
    empty-folder creation, pre-publication hash verification through the
    staging helper, and the progress callback. Uses TestDrive folders only.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    $script:OutputLanguage = 'en'
    $script:MessagesPath = ''
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-FileSha256.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\nextcloud\internal\Get-FolderInventory.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\nextcloud\internal\Copy-FileToStaging.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\nextcloud\internal\Copy-ChangedFile.ps1')

    function Invoke-Copy {
        param([string] $Source, [string] $Destination, [scriptblock] $Reporter)
        $sourceInventory = Get-FolderInventory -Path $Source
        $destinationInventory = Get-FolderInventory -Path $Destination
        $parameters = @{
            Source = $Source
            Destination = $Destination
            SourceInventory = $sourceInventory
            DestinationInventory = $destinationInventory
            FolderName = 'Test'
        }
        if ($null -ne $Reporter) { $parameters['ProgressReporter'] = $Reporter }
        Copy-ChangedFile @parameters
    }
}

Describe 'Copy-ChangedFile' {
    BeforeEach {
        $script:Source = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Destination = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:Source, $script:Destination | Out-Null
    }

    It 'skips a file whose identical content already exists at the destination' {
        [System.IO.File]::WriteAllText((Join-Path $script:Source 'same.txt'), 'same')
        [System.IO.File]::WriteAllText((Join-Path $script:Destination 'same.txt'), 'same')

        $result = Invoke-Copy -Source $script:Source -Destination $script:Destination

        $result.IdenticalFiles | Should -Be 1
        $result.CopiedFiles | Should -Be 0
        $result.CopiedBytes | Should -Be 0
    }

    It 'finds identical content under a different destination name' {
        [System.IO.File]::WriteAllText((Join-Path $script:Source 'new-name.txt'), 'moved')
        [System.IO.File]::WriteAllText((Join-Path $script:Destination 'old-name.txt'), 'moved')

        $result = Invoke-Copy -Source $script:Source -Destination $script:Destination

        $result.IdenticalFiles | Should -Be 1
        $result.CopiedFiles | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:Destination 'new-name.txt') | Should -BeFalse
    }

    It 'copies a new file and verifies its content' {
        [System.IO.File]::WriteAllText((Join-Path $script:Source 'new.txt'), 'fresh content')

        $result = Invoke-Copy -Source $script:Source -Destination $script:Destination

        $result.CopiedFiles | Should -Be 1
        $result.IdenticalFiles | Should -Be 0
        $result.CopiedBytes | Should -Be ([System.Text.Encoding]::UTF8.GetByteCount('fresh content'))
        [System.IO.File]::ReadAllText((Join-Path $script:Destination 'new.txt')) | Should -Be 'fresh content'
    }

    It 'copies only one of two source files with the same content' {
        [System.IO.File]::WriteAllText((Join-Path $script:Source 'a.txt'), 'twin')
        [System.IO.File]::WriteAllText((Join-Path $script:Source 'b.txt'), 'twin')

        $result = Invoke-Copy -Source $script:Source -Destination $script:Destination

        $result.CopiedFiles | Should -Be 1
        $result.IdenticalFiles | Should -Be 1
    }

    It 'copies a file with the same size but different content' {
        [System.IO.File]::WriteAllText((Join-Path $script:Source 'size.txt'), 'AAAA')
        [System.IO.File]::WriteAllText((Join-Path $script:Destination 'size.txt'), 'BBBB')

        $result = Invoke-Copy -Source $script:Source -Destination $script:Destination

        $result.CopiedFiles | Should -Be 1
        [System.IO.File]::ReadAllText((Join-Path $script:Destination 'size.txt')) | Should -Be 'AAAA'
    }

    It 'creates empty source subfolders at the destination' {
        New-Item -ItemType Directory -Path (Join-Path $script:Source 'empty\nested') -Force | Out-Null

        Invoke-Copy -Source $script:Source -Destination $script:Destination | Out-Null

        Test-Path -LiteralPath (Join-Path $script:Destination 'empty\nested') -PathType Container | Should -BeTrue
    }

    It 'reports progress and a final completion through the reporter' {
        [System.IO.File]::WriteAllText((Join-Path $script:Source 'p.txt'), 'progress')
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $reporter = {
            param([string] $Activity, [string] $Status, [int] $PercentComplete, [switch] $Completed)
            $script:Calls.Add([pscustomobject]@{ Activity = $Activity; Completed = [bool]$Completed })
        }

        Invoke-Copy -Source $script:Source -Destination $script:Destination -Reporter $reporter | Out-Null

        $script:Calls.Count | Should -BeGreaterOrEqual 2
        $script:Calls[0].Activity | Should -Be 'Copying folder Test'
        $script:Calls[-1].Completed | Should -BeTrue
    }

    It 'throws when a source file changes during the identical-content check' {
        [System.IO.File]::WriteAllText((Join-Path $script:Source 'moving.txt'), 'content')
        [System.IO.File]::WriteAllText((Join-Path $script:Destination 'moving.txt'), 'content')
        $script:HashCalls = 0
        Mock Get-FileSha256 {
            if ($Path -like "$script:Source*") {
                $script:HashCalls++
                if ($script:HashCalls -eq 1) { return 'AAA' }
                return 'BBB'
            }
            return 'AAA'
        }

        {
            Copy-ChangedFile -Source $script:Source -Destination $script:Destination `
                -SourceInventory (Get-FolderInventory -Path $script:Source) `
                -DestinationInventory (Get-FolderInventory -Path $script:Destination) `
                -FolderName 'Test' } | Should -Throw -ExpectedMessage '*Source file changed*'
    }

}
