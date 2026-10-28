# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>
<#
.SYNOPSIS
    Unit tests for media\internal\New-MediaDateFileName.ps1.

.DESCRIPTION
    Verifies the requested filename format and collision avoidance.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\common\internal\Get-LocalizedText.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\New-MediaDateCode.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\New-MediaDateFileName.ps1')
}

Describe 'New-MediaDateFileName' {
    It 'builds a date-based name with the original extension' {
        $result = New-MediaDateFileName -DateTime ([datetime]'2021-06-07T08:09:10') `
            -DirectoryPath $TestDrive -Extension '.jpg'

        $result.FileName | Should -Match '^21-06-07 08-09-10 [0-9A-Z]{4}\.jpg$'
        $result.FullPath | Should -Be (Join-Path $TestDrive $result.FileName)
    }

    It 'chooses another code when the target already exists' {
        $script:codeCounter = 0
        Mock New-MediaDateCode {
            if ($script:codeCounter -eq 0)
            {
                $script:codeCounter++
                return 'ABCD'
            }
            return 'EFGH'
        }
        $existingPath = Join-Path $TestDrive '21-06-07 08-09-10 ABCD.mov'
        $null = New-Item -ItemType File -Path $existingPath

        $result = New-MediaDateFileName -DateTime ([datetime]'2021-06-07T08:09:10') `
            -DirectoryPath $TestDrive -Extension '.mov'

        $result.FileName | Should -Be '21-06-07 08-09-10 EFGH.mov'
    }
}
