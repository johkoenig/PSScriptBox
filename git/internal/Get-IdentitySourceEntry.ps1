<#
.SYNOPSIS
    Collects identity value sources for the Git configuration script.

.DESCRIPTION
    Defines Get-IdentitySourceEntry. The function reads the existing Git settings
    and the account sources for user.name or user.email and returns them in
    priority order, without filtering.

.NOTES
    Dependencies: Git for Windows (git.exe), Windows, and the helper functions
    Get-GitConfigValue, Get-AccountNameFormat, Get-LocalAccountFullName, and
    Get-MicrosoftAccountName in git\internal, loaded by the caller.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Returns the candidate sources for a Git identity value.

.DESCRIPTION
    Existing Git settings come first so that pressing Enter keeps the former
    value. For user.name the sources are the Active Directory display name, the
    Windows display name, and the full name of a local account. For user.email
    they are the Active Directory mail attribute, the user principal name, and
    the signed-in Microsoft accounts. Entries with empty or invalid values are
    returned unchanged; Get-IdentityCandidate filters them.

    Source labels are English templates; Get-IdentityCandidate localizes them.

.PARAMETER Key
    user.name or user.email.

.PARAMETER Scope
    Local (repository) or Global. Local also includes the global and system
    settings; Global includes the system settings.

.PARAMETER Repository
    Root path of the repository when the scope is Local.

.PARAMETER UserName
    Name of the signed-in account.

.PARAMETER UserDomainName
    Domain of the signed-in account.

.PARAMETER MachineName
    Name of this computer.

.PARAMETER DirectoryInfo
    Directory lookup result from Get-DirectoryUserInfo with DisplayName and Mail.

.PARAMETER Language
    'de' selects German error text for unreadable settings; any other value selects English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    PSCustomObject[] with Value, Source, and SourceArguments properties.
#>
function Get-IdentitySourceEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('user.name', 'user.email')][string] $Key,
        [Parameter(Mandatory)][ValidateSet('Local', 'Global')][string] $Scope,
        [string] $Repository,
        [Parameter(Mandatory)][string] $UserName,
        [Parameter(Mandatory)][string] $UserDomainName,
        [Parameter(Mandatory)][string] $MachineName,
        [Parameter(Mandatory)][object] $DirectoryInfo,
        [string] $Language = 'en',
        [string]$MessagesPath = ''
    )

    $entries = [System.Collections.Generic.List[object]]::new()
    $scopes = if ($Scope -eq 'Local') { @('Local', 'Global', 'System') } else { @('Global', 'System') }
    foreach ($existingScope in $scopes) {
        $entries.Add([pscustomobject]@{
            Value = Get-GitConfigValue -Key $Key -Scope $existingScope -Repository $Repository -Language $Language -MessagesPath $MessagesPath
                Source          = 'Existing Git setting ({0})'
                SourceArguments = @($existingScope)
            })
    }

    if ($Key -eq 'user.name') {
        $entries.Add([pscustomobject]@{ Value = $DirectoryInfo.DisplayName; Source = 'Active Directory display name'; SourceArguments = @() })
        $entries.Add([pscustomobject]@{ Value = (Get-AccountNameFormat -Format 3); Source = 'Windows display name'; SourceArguments = @() })
        # A local account has no directory entry, so its full name is read from the local account database.
        if ($UserDomainName -eq $MachineName) {
            $entries.Add([pscustomobject]@{
                    Value           = Get-LocalAccountFullName -UserName $UserName -MachineName $MachineName
                    Source          = 'Windows display name'
                    SourceArguments = @()
                })
        }
    }
    else {
        $entries.Add([pscustomobject]@{ Value = $DirectoryInfo.Mail; Source = 'Active Directory email'; SourceArguments = @() })
        $entries.Add([pscustomobject]@{ Value = (Get-AccountNameFormat -Format 8); Source = 'User principal name'; SourceArguments = @() })
        foreach ($account in Get-MicrosoftAccountName) {
            $entries.Add([pscustomobject]@{ Value = $account; Source = 'Microsoft account'; SourceArguments = @() })
        }
    }
    return $entries.ToArray()
}
