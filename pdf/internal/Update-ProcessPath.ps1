<#
.SYNOPSIS
    Provides the PATH refresh helper for the PDF processor setup.

.DESCRIPTION
    Defines Update-ProcessPath, which replaces the PATH of the current process with
    the given machine and user values.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Refreshes the PATH of the current process.

.DESCRIPTION
    Replaces the process PATH with the given machine and user PATH values, so that
    executables installed by Chocolatey become visible to this setup process.
    The caller reads the registry values and passes them in.

.PARAMETER MachinePath
    Machine-wide PATH value.

.PARAMETER UserPath
    Current-user PATH value.

.OUTPUTS
    None. Sets $env:Path as a side effect.
#>
function Update-ProcessPath {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [string] $MachinePath = '',
        [string] $UserPath = ''
    )

    $newPath = @($MachinePath, $UserPath) -join [System.IO.Path]::PathSeparator
    if ( $PSCmdlet.ShouldProcess('Process PATH', 'Refresh'))
    {
        $env:Path = $newPath
    }
}
