<#
.SYNOPSIS
    Provides the process argument quoting helper for the PDF scripts.

.DESCRIPTION
    Defines ConvertTo-QuotedArgument, which builds ProcessStartInfo.Arguments
    values for external programs.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Formats an argument for ProcessStartInfo.Arguments.

.DESCRIPTION
    Encloses an argument in quotation marks and escapes embedded quotation
    marks and trailing backslashes for Windows PowerShell 5.1, so the value is
    passed as a single process argument.

.PARAMETER Value
    Argument text to quote.

.OUTPUTS
    System.String. The correctly quoted argument.
#>
function ConvertTo-QuotedArgument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Value)

    # Double each backslash immediately before a quotation mark.
    $escaped = [regex]::Replace($Value, '(\\)(?=")', '$1$1')
    # Double any remaining trailing backslashes.
    if ($escaped.EndsWith('\')) { $escaped = $escaped + '\' }
    # Escape embedded quotation marks.
    $escaped = $escaped -replace '"', '\"'
    return '"' + $escaped + '"'
}
