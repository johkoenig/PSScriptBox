# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Unit tests for nextcloud\internal\Test-FileReadAccess.ps1.

.DESCRIPTION
    Covers readable files, files locked by another handle, directories used as
    files, and localized reasons. Uses TestDrive files only.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    $script:OutputLanguage = 'en'
    $script:MessagesPath = ''
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\nextcloud\internal\Test-FileReadAccess.ps1')
}

Describe 'Test-FileReadAccess' {
    It 'returns nothing for a readable file' {
        $path = Join-Path $TestDrive 'readable.txt'
        [System.IO.File]::WriteAllText($path, 'data')
        @(Test-FileReadAccess -Path $path).Count | Should -Be 0
    }

    It 'reports a file that another process holds exclusively' {
        $path = Join-Path $TestDrive 'locked.txt'
        [System.IO.File]::WriteAllText($path, 'data')
        $lock = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $problem = Test-FileReadAccess -Path $path
            $problem.Path | Should -Be $path
            $problem.Reason | Should -Match '^File cannot be read: '
        }
        finally {
            $lock.Dispose()
        }
    }

    It 'reports a directory that cannot be opened as a file' {
        $directory = Join-Path $TestDrive 'folder'
        New-Item -ItemType Directory -Path $directory | Out-Null
        $problem = Test-FileReadAccess -Path $directory
        $problem.Path | Should -Be $directory
        $problem.Reason | Should -Be 'No read permission on file'
    }

    It 'uses the German catalog when Language is de' {
        $path = Join-Path $TestDrive 'german.txt'
        [System.IO.File]::WriteAllText($path, 'data')
        $messages = Join-Path $PSScriptRoot '..\..\..\nextcloud\l10n\de-DE\Messages.psd1'
        $directory = Join-Path $TestDrive 'german-folder'
        New-Item -ItemType Directory -Path $directory | Out-Null
        $problem = Test-FileReadAccess -Path $directory -Language 'de' -MessagesPath $messages
        $problem.Reason | Should -Be 'Keine Leseberechtigung für die Datei'
    }
}
