# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Get-DirectoryUserInfo.ps1.

.DESCRIPTION
    Covers the local-account shortcut and the unreachable-directory fallback.
    No real directory is queried.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-DirectoryUserInfo.ps1')
}

Describe 'Get-DirectoryUserInfo' {
    It 'returns empty values for a local account without querying a directory' {
        $result = Get-DirectoryUserInfo -UserName 'ann' -UserDomainName 'PC01' -MachineName 'PC01'
        $result.DisplayName | Should -Be ''
        $result.Mail | Should -Be ''
    }

    It 'returns empty values when the directory cannot be reached' {
        $result = Get-DirectoryUserInfo -UserName 'ann' -UserDomainName 'scriptbox-test.invalid' -MachineName 'PC01'
        $result.DisplayName | Should -Be ''
        $result.Mail | Should -Be ''
    }

    It 'returns an object with DisplayName and Mail properties' {
        $result = Get-DirectoryUserInfo -UserName 'ann' -UserDomainName 'PC01' -MachineName 'PC01'
        $result.PSObject.Properties.Name | Should -Be @('DisplayName', 'Mail')
    }
}
