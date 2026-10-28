# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Runs the scriptbox test suite with Pester.

.DESCRIPTION
    Checks that Pester 5 or later is available and runs the static checks,
    unit tests, and safety tests in this folder. With -Coverage, code coverage
    is measured for all internal helper functions. The script does not install
    anything; missing dependencies are reported with an install hint.

.PARAMETER Path
    Test files or folder to run. Defaults to this folder.

.PARAMETER Tag
    Runs only tests with the given Pester tag.

.PARAMETER Coverage
    Measures code coverage for all internal\*.ps1 files and prints a summary.

.EXAMPLE
    .\tests\Invoke-Tests.ps1
    Runs all tests with detailed output.

.EXAMPLE
    .\tests\Invoke-Tests.ps1 -Path .\tests\nextcloud\Remove-MigratedUserData.Tests.ps1
    Runs only the safety tests for deleting empty folders.

.EXAMPLE
    .\tests\Invoke-Tests.ps1 -Coverage
    Runs all tests and reports coverage for the internal helper functions.

.NOTES
    Dependencies: Pester 5 or later (Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser).
    The tests run on Windows PowerShell 5.1 and PowerShell 7.
#>

[CmdletBinding()]
param(
    [string[]] $Path,
    [string[]] $Tag,
    [switch] $Coverage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

    # Windows PowerShell 5.1 does not resolve $PSScriptRoot in the param default, so the default is set here.
    if (-not $Path) { $Path = @($PSScriptRoot) }

# Pester 3.x ships with Windows PowerShell and would be loaded by default, so the minimum version is enforced here.
$pester = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0' } |
    Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $pester) {
    $message = @(
        'Pester 5 or later is required but was not found.'
        'Install it once in a user shell (no administrator rights needed):'
        '    Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser'
    ) -join [System.Environment]::NewLine
    Write-Error -Message $message -ErrorAction Continue
    exit 1
}
Import-Module -Name $pester.Path -MinimumVersion 5.0 -Force

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
if ($Tag) { $config.Filter.Tag = $Tag }

# Coverage covers only internal helpers, because top-level scripts run their main flow at import time.
if ($Coverage) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter '*.ps1' -File |
            Where-Object { $_.FullName -match '\\internal\\' -and $_.FullName -notmatch '\\(\.git|tests)\\' } |
            ForEach-Object { $_.FullName })
    # Keeps the JaCoCo report out of the repository (Pester's default is coverage.xml in the working directory).
    $config.CodeCoverage.OutputPath = Join-Path ([System.IO.Path]::GetTempPath()) 'scriptbox-coverage.xml'
}

Invoke-Pester -Configuration $config
