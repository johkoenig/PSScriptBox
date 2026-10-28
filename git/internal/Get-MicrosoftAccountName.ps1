<#
.SYNOPSIS
    Reads signed-in Microsoft account addresses for the Git configuration script.

.DESCRIPTION
    Defines Get-MicrosoftAccountName. The function lists the account names stored
    under the current user's IdentityCRL registry key.

.NOTES
    Dependencies: Windows only; Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Lists the Microsoft accounts signed in on this computer.

.DESCRIPTION
    Reads the child key names of the IdentityCRL user properties in the current
    user's registry hive. Returns an empty array when the key is missing.

.OUTPUTS
    System.String[]. Account names, typically email addresses.
#>
function Get-MicrosoftAccountName {
    [CmdletBinding()]
    param()

    $identityKey = 'HKCU:\Software\Microsoft\IdentityCRL\UserExtendedProperties'
    try {
        if (-not (Test-Path -LiteralPath $identityKey)) { return @() }
        return @(Get-ChildItem -LiteralPath $identityKey | ForEach-Object { [string] $_.PSChildName })
    }
    catch {
        Write-Verbose $_.Exception.Message
        return @()
    }
}
