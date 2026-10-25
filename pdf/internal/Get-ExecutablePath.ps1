<#
.SYNOPSIS
    Provides the executable lookup helper for the PDF scripts.

.DESCRIPTION
    Defines Get-ExecutablePath, which resolves a command name through the
    current PATH.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Finds an executable in the current PATH.

.DESCRIPTION
    Returns the path of the first matching command, or null when no command is
    available.

.PARAMETER Name
    Executable command name.

.OUTPUTS
    System.String or null.
#>
function Get-ExecutablePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) { return $null }
    return $command.Source
}
