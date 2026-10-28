<#
.SYNOPSIS
    Generates a random uppercase media date code.

.DESCRIPTION
    Defines New-MediaDateCode, which creates a four-character uppercase
    alphanumeric code for a restored media filename.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Creates a random uppercase four-character code.

.DESCRIPTION
    Selects four characters from the digits 0-9 and uppercase letters A-Z.

.OUTPUTS
    System.String.
#>
function New-MediaDateCode
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'Generates a value only and does not change system state.'
    )]
    param()

    $characters = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $code = for ($index = 0; $index -lt 4; $index++)
    {
        $characters[(Get-Random -Minimum 0 -Maximum $characters.Length)]
    }
    -join $code
}
