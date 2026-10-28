<#
.SYNOPSIS
    Reads the full name of a local Windows account for the Git configuration script.

.DESCRIPTION
    Defines Get-LocalAccountFullName. The function reads the FullName property
    of a local account through the WinNT ADSI provider.

.NOTES
    Dependencies: Windows only; Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Returns the full name of a local account.

.DESCRIPTION
    Reads the FullName property of a local user through ADSI. Returns an empty
    string when the account does not exist or the property cannot be read.

.PARAMETER UserName
    Local account name.

.PARAMETER MachineName
    Name of the computer that owns the local account.

.OUTPUTS
    System.String. The full name or an empty string.
#>
function Get-LocalAccountFullName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $UserName,
        [Parameter(Mandatory)][string] $MachineName
    )

    try {
        $local = [ADSI]('WinNT://{0}/{1},user' -f $MachineName, $UserName)
        return [string] $local.FullName.Value
    }
    catch {
        Write-Verbose $_.Exception.Message
        return ''
    }
}
