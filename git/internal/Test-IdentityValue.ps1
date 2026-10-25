<#
.SYNOPSIS
    Tests whether an identity value is acceptable for the Git configuration script.

.DESCRIPTION
    Defines Test-IdentityValue. Names must be non-empty; email addresses must
    look like a valid address.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Tests whether an identity value is acceptable.

.DESCRIPTION
    Names must be non-empty; email addresses must look like a valid address.
    The email check is a simple shape test (local part, @, domain with a dot),
    not an RFC 5322 validation.

.PARAMETER Key
    user.name or user.email.

.PARAMETER Value
    Value to validate. Surrounding whitespace is ignored for email addresses.

.OUTPUTS
    System.Boolean. True when the value is acceptable.
#>
function Test-IdentityValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('user.name', 'user.email')][string] $Key,
        [AllowEmptyString()][string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Key -eq 'user.email') { return ($Value.Trim() -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') }
    return $true
}
