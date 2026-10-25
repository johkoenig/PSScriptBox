# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for git\internal\Get-IdentitySourceEntry.ps1.

.DESCRIPTION
    Replaces the Git, registry, and account helpers with mocks, so the source
    order and the local-account branch are tested without the directory.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-GitConfigValue.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-AccountNameFormat.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-LocalAccountFullName.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-MicrosoftAccountName.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\git\internal\Get-IdentitySourceEntry.ps1')

    $script:DomainAccount = @{
        Key = 'user.name'; Scope = 'Local'; Repository = 'C:\repo'; UserName = 'ann'
        UserDomainName = 'CONTOSO'; MachineName = 'PC01'
        DirectoryInfo = [pscustomobject]@{ DisplayName = 'Ann Lee (AD)'; Mail = 'ann@contoso.test' }
    }
}

Describe 'Get-IdentitySourceEntry' {
    BeforeEach {
        Mock Get-GitConfigValue { param($Key, $Scope) return "existing-$Scope" }
        Mock Get-AccountNameFormat { param($Format) return "format-$Format" }
        Mock Get-LocalAccountFullName { return 'Ann Local' }
        Mock Get-MicrosoftAccountName { return @('ann@contoso.test', 'ann@fabrikam.test') }
    }

    It 'lists local, global, and system settings first for the Local scope' {
        $entries = @(Get-IdentitySourceEntry @script:DomainAccount)
        $entries[0].Value | Should -Be 'existing-Local'
        $entries[1].Value | Should -Be 'existing-Global'
        $entries[2].Value | Should -Be 'existing-System'
        $entries[0].SourceArguments[0] | Should -Be 'Local'
    }

    It 'lists only global and system settings for the Global scope' {
        $account = $script:DomainAccount.Clone()
        $account.Scope = 'Global'
        $account.Repository = ''
        $entries = @(Get-IdentitySourceEntry @account)
        $entries.Count | Should -Be 4
        $entries[0].Value | Should -Be 'existing-Global'
        $entries[1].Value | Should -Be 'existing-System'
    }

    It 'adds the directory display name and the Windows display name for a domain account' {
        $entries = @(Get-IdentitySourceEntry @script:DomainAccount)
        $entries.Count | Should -Be 5
        $entries[3].Value | Should -Be 'Ann Lee (AD)'
        $entries[3].Source | Should -Be 'Active Directory display name'
        $entries[4].Value | Should -Be 'format-3'
        $entries[4].Source | Should -Be 'Windows display name'
        Should -Invoke Get-LocalAccountFullName -Times 0 -Exactly
    }

    It 'adds the local account full name for a local account' {
        $account = $script:DomainAccount.Clone()
        $account.UserDomainName = 'PC01'
        $entries = @(Get-IdentitySourceEntry @account)
        $entries.Count | Should -Be 6
        $entries[5].Value | Should -Be 'Ann Local'
        $entries[5].Source | Should -Be 'Windows display name'
        Should -Invoke Get-LocalAccountFullName -Times 1 -Exactly
    }

    It 'lists directory mail, user principal name, and Microsoft accounts for user.email' {
        $account = $script:DomainAccount.Clone()
        $account.Key = 'user.email'
        $entries = @(Get-IdentitySourceEntry @account)
        $entries.Count | Should -Be 7
        $entries[3].Value | Should -Be 'ann@contoso.test'
        $entries[3].Source | Should -Be 'Active Directory email'
        $entries[4].Value | Should -Be 'format-8'
        $entries[4].Source | Should -Be 'User principal name'
        $entries[5].Value | Should -Be 'ann@contoso.test'
        $entries[5].Source | Should -Be 'Microsoft account'
        $entries[6].Value | Should -Be 'ann@fabrikam.test'
    }

    It 'passes the language and catalog to the Git helper' {
        $account = $script:DomainAccount.Clone()
        $account.Language = 'de'
        $account.Messages = @{}
        Get-IdentitySourceEntry @account | Out-Null
        Should -Invoke Get-GitConfigValue -ParameterFilter { $Language -eq 'de' } -Times 3 -Exactly
    }
}
