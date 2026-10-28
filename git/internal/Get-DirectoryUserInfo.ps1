<#
.SYNOPSIS
    Reads directory attributes for the Git configuration script.

.DESCRIPTION
    Defines Get-DirectoryUserInfo. The function queries Active Directory for the
    mail and displayName attributes of the account passed in by the caller.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7 with
    System.DirectoryServices; domain-joined computers only.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Looks up a user in Active Directory.

.DESCRIPTION
    Queries the user's mail and displayName attributes on domain-joined
    computers. Returns empty values when the computer is not domain-joined or
    the directory is unreachable. The account data is passed in by the caller
    so that the function does not read the current user's environment.

.PARAMETER UserName
    sAMAccountName of the account to look up.

.PARAMETER UserDomainName
    Domain of the signed-in account.

.PARAMETER MachineName
    Name of this computer. Equal to UserDomainName for local accounts, which
    are not looked up in a directory.

.OUTPUTS
    PSCustomObject with DisplayName and Mail properties.
#>
function Get-DirectoryUserInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $UserName,
        [Parameter(Mandatory)][string] $UserDomainName,
        [Parameter(Mandatory)][string] $MachineName
    )

    $result = [pscustomobject]@{ DisplayName = ''; Mail = '' }
    if ($UserDomainName -eq $MachineName) { return $result }
    $searcher = $null
    try {
        Add-Type -AssemblyName System.DirectoryServices
        # Escape LDAP filter metacharacters so that unusual account names cannot alter the filter.
        $account = $UserName -replace '([\\*()])', '\$1'
        $searcher = [System.DirectoryServices.DirectorySearcher]::new()
        $searcher.Filter = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$account))"
        $searcher.ClientTimeout = [TimeSpan]::FromSeconds(5)
        [void] $searcher.PropertiesToLoad.AddRange([string[]] @('mail', 'displayName'))
        $entry = $searcher.FindOne()
        if ($entry) {
            if ($entry.Properties['mail'].Count -gt 0) { $result.Mail = [string] $entry.Properties['mail'][0] }
            if ($entry.Properties['displayName'].Count -gt 0) { $result.DisplayName = [string] $entry.Properties['displayName'][0] }
        }
    }
    catch {
        Write-Verbose $_.Exception.Message
    }
    finally {
        if ($searcher) { $searcher.Dispose() }
    }
    return $result
}
