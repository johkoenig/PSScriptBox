<#
.SYNOPSIS
    Formats a localized missing-dependency report.

.DESCRIPTION
    Returns the dependency name and installation guidance for display by a
    user-facing script. The localized message template is supplied by the
    caller so each tool can use its own message catalog. The function does not
    write to the console.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Creates a localized missing-dependency report.

.DESCRIPTION
    Formats the supplied localized message template and returns the installation
    guidance without performing console output.

.PARAMETER Dependency
    Name of the missing executable, application, or module.

.PARAMETER Guidance
    Localized installation command, download link, or other actionable guidance.

.PARAMETER MessageTemplate
    Localized message template containing a '{0}' placeholder for the dependency.

.OUTPUTS
    PSCustomObject with the dependency name, localized message, and guidance.
#>
function Get-MissingDependencyReport
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Dependency,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Guidance,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $MessageTemplate
    )

    [pscustomobject]@{
        Dependency = $Dependency
        Message = $MessageTemplate -f $Dependency
        Guidance = $Guidance
    }
}
