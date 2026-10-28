<#
.SYNOPSIS
    Runs a Git command for the Git configuration script.

.DESCRIPTION
    Defines Invoke-GitCommand. The function calls git.exe, captures its output,
    and throws a localized error when Git exits with a non-zero code.

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
    Runs a Git command, optionally for a specific repository.

.DESCRIPTION
    Captures command output and checks Git's exit code so failures are reported
    instead of being mistaken for successful configuration.

.PARAMETER Repository
    Root path of the Git repository. Omit for commands independent of a repository.

.PARAMETER Arguments
    Arguments passed to Git.

.PARAMETER Language
    'de' selects German error text; any other value selects English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    System.String[]. Lines emitted by Git.
#>
function Invoke-GitCommand {
    [CmdletBinding()]
    param(
        [string] $Repository,
        [Parameter(Mandatory)][string[]] $Arguments,
        [string] $Language = 'en',
        [string]$MessagesPath = ''
    )

    $prefix = if ($Repository) { @('-C', $Repository) } else { @() }
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Git writes diagnostics to stderr; with 'Stop' Windows PowerShell 5.1 would turn them into terminating errors.
        $ErrorActionPreference = 'Continue'
        $output = @(& git @prefix @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        $details = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw (Get-LocalizedText -Text 'Git command failed (exit code {0}): {1}' -Arguments @($exitCode, $details) -Language $Language -MessagesPath $MessagesPath)
    }
    return $output
}
