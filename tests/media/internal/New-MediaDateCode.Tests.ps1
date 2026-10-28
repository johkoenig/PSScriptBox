# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>
<#
.SYNOPSIS
    Unit tests for media\internal\New-MediaDateCode.ps1.

.DESCRIPTION
    Verifies random code length and the allowed uppercase character set.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\media\internal\New-MediaDateCode.ps1')
}

Describe 'New-MediaDateCode' {
    It 'returns four uppercase alphanumeric characters' {
        $code = New-MediaDateCode

        $code | Should -Match '^[0-9A-Z]{4}$'
    }
}
