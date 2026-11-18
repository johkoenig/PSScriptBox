<#
.SYNOPSIS
    PSScriptBox script module: loads all PSScriptBox commands.

.DESCRIPTION
    Dot-sources every internal helper file and every public command file of the
    repository, then exports only the public commands; internal helpers stay
    module-private. Each public command file is dual-mode: dot-sourcing it defines
    the command function without running the flow, so importing this module never
    starts a command.

.EXAMPLE
    Import-Module .\PSScriptBox.psd1
    Imports the module from a repository checkout; afterwards all commands, for
    example Remove-ObsoleteGitBranches, are available by name.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Internal helpers first: each of these files contains exactly one function and no top-level flow.
$internalFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File -Filter '*.ps1' |
        Where-Object { $_.FullName -match '[\\/]internal[\\/]' -and $_.FullName -notmatch '[\\/](tests|\.git)[\\/]' } |
        Sort-Object -Property FullName)
foreach ($internalFile in $internalFiles)
{
    . $internalFile.FullName
}

# Public command files: dot-sourcing defines the command function; their direct-run guard is skipped.
$publicFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File -Filter '*.ps1' |
        Where-Object { $_.FullName -notmatch '[\\/]internal[\\/]' -and $_.FullName -notmatch '[\\/](tests|\.git)[\\/]' } |
        Sort-Object -Property FullName)
foreach ($publicFile in $publicFiles)
{
    . $publicFile.FullName
}

$exportedFunctions = @($publicFiles | ForEach-Object { $_.BaseName })
Export-ModuleMember -Function $exportedFunctions
