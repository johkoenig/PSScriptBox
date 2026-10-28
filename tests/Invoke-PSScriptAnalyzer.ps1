<#
.SYNOPSIS
    Analyzes repository PowerShell scripts with PSScriptAnalyzer.

.DESCRIPTION
    Runs PSScriptAnalyzer on production PowerShell scripts outside the tests
    directory. The script requires PSScriptAnalyzer 1.21 or later, does not
    install dependencies, and exits with code 1 when the analyzer reports
    errors or warnings.

.EXAMPLE
    .\tests\Invoke-PSScriptAnalyzer.ps1
    Analyzes production PowerShell scripts and fails if errors or warnings exist.

.NOTES
    Dependencies: PSScriptAnalyzer 1.21 or later
    (Install-Module PSScriptAnalyzer -MinimumVersion 1.21.0 -Scope CurrentUser).
    Runs on Windows PowerShell 5.1 and PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

#Requires -Version 5.1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'This user-facing script reports status using color-coded console output.'
)]
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$banner = @(
    '  +--------------------------------------------------+'
    '  |  | POWERSHELL SCRIPT ANALYZER              |  |'
    '  |  | CHECK SOURCE AND REPORT FINDINGS        |  |'
    '  +--------------------------------------------------+'
)
foreach ($line in $banner)
{
    Write-Host $line -ForegroundColor Cyan
}
Write-Host 'Analyzes PowerShell scripts and reports analyzer findings.' -ForegroundColor Cyan
Write-Host ''

$repoRoot = Split-Path -Parent $PSScriptRoot
Write-Host '=== PSScriptAnalyzer: processing started ===' -ForegroundColor Cyan
Write-Host "Path: $repoRoot"

$analyzerModule = Get-Module -ListAvailable -Name PSScriptAnalyzer |
        Where-Object { $_.Version -ge [version]'1.21.0' } |
        Sort-Object Version -Descending |
        Select-Object -First 1
if ($null -eq $analyzerModule)
{
    $message = @(
        'PSScriptAnalyzer 1.21 or later is required but was not found.'
        'Install it once in a user shell (no administrator rights needed):'
        '    Install-Module PSScriptAnalyzer -MinimumVersion 1.21.0 -Scope CurrentUser'
    ) -join [System.Environment]::NewLine
    Write-Error -Message $message -ErrorAction Continue
    exit 1
}

try
{
    Import-Module -Name $analyzerModule.Path -Force -ErrorAction Stop
}
catch
{
    Write-Error -Message "PSScriptAnalyzer could not be loaded: $( $_.Exception.Message )" -ErrorAction Continue
    exit 1
}

$scriptFiles = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter '*.ps1' -File |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|tests)[\\/]' })
Write-Host "Number of files: $( $scriptFiles.Count )"

try
{
    $findings = @(
    foreach ($scriptFile in $scriptFiles)
    {
        Invoke-ScriptAnalyzer -Path $scriptFile.FullName -Severity Error, Warning, ParseError -ErrorAction Stop
    }
    )
}
catch
{
    Write-Error -Message "PSScriptAnalyzer failed: $( $_.Exception.Message )" -ErrorAction Continue
    exit 1
}

Write-Host '=== Summary ===' -ForegroundColor Cyan
Write-Host "Path: $repoRoot"
Write-Host "Analyzed: $( $scriptFiles.Count ) files"

$errorCount = @($findings | Where-Object Severity -in @('Error', 'ParseError')).Count
$warningCount = @($findings | Where-Object Severity -eq 'Warning').Count
Write-Host "Errors: $errorCount, warnings: $warningCount"

if ($findings.Count -gt 0)
{
    $findings |
            Sort-Object ScriptName, Line, Column |
            Format-Table ScriptName, Line, Column, RuleName, Severity, Message -Wrap -AutoSize |
            Out-Host
    Write-Error -Message 'PSScriptAnalyzer found errors or warnings.' -ErrorAction Continue
    exit 1
}

Write-Host 'No analyzer warnings or errors found.' -ForegroundColor Green
