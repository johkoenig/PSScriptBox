<#
.SYNOPSIS
    Reads account name formats for the Git configuration script.

.DESCRIPTION
    Defines Get-AccountNameFormat. The function calls the Windows GetUserNameEx
    API (secur32.dll) for the signed-in account.

.NOTES
    Dependencies: Windows only; Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Reads a name format of the signed-in Windows account.

.DESCRIPTION
    Calls the Windows GetUserNameEx API, which works for local, Active
    Directory, and Entra ID (Azure AD) sign-ins and returns nothing when the
    format is unavailable.

.PARAMETER Format
    EXTENDED_NAME_FORMAT value: 3 for display name, 8 for user principal name.

.OUTPUTS
    System.String. The name or an empty string.
#>
function Get-AccountNameFormat {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int] $Format)

    try {
        if (-not ('Scriptbox.AccountNames' -as [type])) {
            Add-Type -Namespace 'Scriptbox' -Name 'AccountNames' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("secur32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern bool GetUserNameEx(int nameFormat, System.Text.StringBuilder userName, ref uint size);
'@
        }
        $builder = [System.Text.StringBuilder]::new(512)
        [uint32] $size = 512
        if ([Scriptbox.AccountNames]::GetUserNameEx($Format, $builder, [ref] $size)) {
            return $builder.ToString().Trim()
        }
    }
    catch {
        Write-Verbose $_.Exception.Message
    }
    return ''
}
