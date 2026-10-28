<#
.SYNOPSIS
    Reads a Git configuration value for the Git configuration script.

.DESCRIPTION
    Defines Get-GitConfigValue. The function calls git.exe config --get for one
    scope and returns the value, or an empty string when the key is not set.

.NOTES
    Dependencies: Git for Windows (git.exe) on PATH, Windows PowerShell 5.1 or
    PowerShell 7, and common\internal\Get-LocalizedText.ps1 loaded by the caller.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Reads a Git configuration value from one scope.

.DESCRIPTION
    Returns the configured value for a key, or an empty string when the key is
    not set in the requested scope.

.PARAMETER Key
    Git configuration key to read.

.PARAMETER Scope
    Local, Global, or System.

.PARAMETER Repository
    Root path of the Git repository; required for the Local scope.

.PARAMETER Language
    'de' selects German error text; any other value selects English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    System.String. The configured value or an empty string.
#>
function Get-GitConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Key,
        [Parameter(Mandatory)][ValidateSet('Local', 'Global', 'System')][string] $Scope,
        [string] $Repository,
        [string] $Language = 'en',
        [string]$MessagesPath = ''
    )

    if ($Scope -eq 'Local' -and -not $Repository) { return '' }
    $prefix = if ($Scope -eq 'Local') { @('-C', $Repository) } else { @() }
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $value = @(& git @prefix config ('--' + $Scope.ToLowerInvariant()) --get $Key 2>$null)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    # Exit code 1 means the key is absent. A missing system config file is not an error for this purpose.
    if ($exitCode -eq 1 -or ($exitCode -ne 0 -and $Scope -eq 'System')) { return '' }
    if ($exitCode -ne 0) {
        throw (Get-LocalizedText -Text 'Could not read Git setting: {0}' -Arguments @($Key) -Language $Language -MessagesPath $MessagesPath)
    }
    return ($value -join [Environment]::NewLine).Trim()
}
