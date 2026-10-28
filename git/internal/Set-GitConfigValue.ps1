<#
.SYNOPSIS
    Writes a Git configuration value for the Git configuration script.

.DESCRIPTION
    Defines Set-GitConfigValue. The function calls git.exe config to store a
    value in the repository-local or global configuration.

.NOTES
    Dependencies: Git for Windows (git.exe) on PATH, Windows PowerShell 5.1 or
    PowerShell 7, and git\internal\Invoke-GitCommand.ps1 and
    common\internal\Get-LocalizedText.ps1 loaded by the caller.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Writes a Git configuration value to the target scope.

.DESCRIPTION
    Stores a value in the repository-local or global Git configuration.

.PARAMETER Key
    Git configuration key to set.

.PARAMETER Value
    Value to store.

.PARAMETER Scope
    Local or Global.

.PARAMETER Repository
    Root path of the Git repository; required for the Local scope.

.PARAMETER Language
    'de' selects German error text; any other value selects English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.OUTPUTS
    System.Boolean. True when the value was written; false when WhatIf or a
    declined confirmation prevented the write.
#>
function Set-GitConfigValue {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string] $Key,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Value,
        [Parameter(Mandatory)][ValidateSet('Local', 'Global')][string] $Scope,
        [string] $Repository,
        [string] $Language = 'en',
        [hashtable] $Messages = @{}
    )

    $action = Get-LocalizedText -Text 'Set Git configuration value {0} to {1}' `
        -Arguments @($Key, $Value) -Language $Language -Messages $Messages
    if (-not $PSCmdlet.ShouldProcess("$Scope $Key", $action))
    {
        return $false
    }

    $repositoryArgument = if ($Scope -eq 'Local') { $Repository } else { '' }
    Invoke-GitCommand -Repository $repositoryArgument `
        -Arguments @('config', ('--' + $Scope.ToLowerInvariant()), $Key, $Value) `
        -Language $Language -Messages $Messages | Out-Null
    return $true
}
