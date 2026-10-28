# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Runs the PSScriptBox test suite with Pester.

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
    Measures code coverage for all internal\*.ps1 files and reports per-file
    executable-line coverage with uncovered line numbers.

.EXAMPLE
    .\tests\Invoke-Tests.ps1
    Runs all tests with detailed output.

.EXAMPLE
    .\tests\Invoke-Tests.ps1 -Path .\tests\nextcloud\Remove-MigratedUserData.Tests.ps1
    Runs only the safety tests for deleting empty folders.

.EXAMPLE
    .\tests\Invoke-Tests.ps1 -Coverage
    Runs all tests and reports executable-line coverage for internal helpers.

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
    $coverageReportPath = Join-Path ([System.IO.Path]::GetTempPath()) "PSScriptBox-coverage-$PID-$([guid]::NewGuid().ToString('N') ).xml"
    $config.CodeCoverage.OutputPath = $coverageReportPath
}

try
{
    Invoke-Pester -Configuration $config

    if ($Coverage)
    {
        $xmlSettings = [System.Xml.XmlReaderSettings]::new()
        $xmlSettings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
        $xmlSettings.XmlResolver = $null
        $xmlReader = [System.Xml.XmlReader]::Create($coverageReportPath, $xmlSettings)
        try
        {
            $coverageDocument = [System.Xml.XmlDocument]::new()
            $coverageDocument.XmlResolver = $null
            $coverageDocument.Load($xmlReader)
        }
        finally
        {
            $xmlReader.Dispose()
        }

        $coverageFiles = @(foreach ($package in $coverageDocument.SelectNodes('/report/package'))
        {
            foreach ($sourceFile in $package.SelectNodes('sourcefile'))
            {
                $lines = @($sourceFile.SelectNodes('line'))
                if ($lines.Count -eq 0)
                {
                    continue
                }

                $coveredLines = @($lines | Where-Object { [int]$_.ci -gt 0 }).Count
                $relativePath = Join-Path ($package.GetAttribute('name') -replace '/', '\') $sourceFile.GetAttribute('name')
                $relativePath = $relativePath -replace '^scriptbox\\', ''
                [pscustomobject]@{
                    Path = $relativePath
                    CoveredLines = $coveredLines
                    TotalLines = $lines.Count
                    MissedLines = @($lines | Where-Object { [int]$_.ci -eq 0 } |
                            ForEach-Object { [int]$_.nr } | Sort-Object -Unique)
                }
            }
        })

        $totalCoveredLines = [int](($coverageFiles | Measure-Object -Property CoveredLines -Sum).Sum)
        $totalLines = [int](($coverageFiles | Measure-Object -Property TotalLines -Sum).Sum)
        $totalPercentage = if ($totalLines -gt 0)
        {
            100 * $totalCoveredLines / $totalLines
        }
        else
        {
            0
        }
        $fullyCoveredFiles = @($coverageFiles | Where-Object { $_.CoveredLines -eq $_.TotalLines }).Count
        $uncoveredFiles = @($coverageFiles | Where-Object { $_.CoveredLines -eq 0 }).Count
        $partlyCoveredFiles = $coverageFiles.Count - $fullyCoveredFiles - $uncoveredFiles

        Write-Host "`nLine coverage (executable lines):"
        foreach ($file in $coverageFiles | Where-Object { $_.CoveredLines -lt $_.TotalLines } | Sort-Object Path)
        {
            $percentage = 100 * $file.CoveredLines / $file.TotalLines
            Write-Host ('  {0}: {1}/{2} lines ({3:N2}%)' -f $file.Path, $file.CoveredLines, $file.TotalLines, $percentage)
            if ($file.MissedLines.Count -gt 0)
            {
                $missedRanges = [System.Collections.Generic.List[string]]::new()
                $rangeStart = $null
                $rangeEnd = $null
                foreach ($lineNumber in $file.MissedLines)
                {
                    if ($null -eq $rangeStart)
                    {
                        $rangeStart = $lineNumber
                        $rangeEnd = $lineNumber
                    }
                    elseif ($lineNumber -eq ($rangeEnd + 1))
                    {
                        $rangeEnd = $lineNumber
                    }
                    else
                    {
                        $missedRanges.Add($( if ($rangeStart -eq $rangeEnd)
                        {
                            "$rangeStart"
                        }
                        else
                        {
                            "$rangeStart-$rangeEnd"
                        } ))
                        $rangeStart = $lineNumber
                        $rangeEnd = $lineNumber
                    }
                }
                $missedRanges.Add($( if ($rangeStart -eq $rangeEnd)
                {
                    "$rangeStart"
                }
                else
                {
                    "$rangeStart-$rangeEnd"
                } ))
                $lineLabel = if ($file.MissedLines.Count -eq 1)
                {
                    'Uncovered line'
                }
                else
                {
                    'Uncovered lines'
                }
                Write-Host ('    {0}: {1}' -f $lineLabel, ($missedRanges -join ', '))
            }
        }

        Write-Host "`nCoverage summary:"
        Write-Host "  Fully covered files: $fullyCoveredFiles"
        Write-Host "  Partly covered files: $partlyCoveredFiles"
        Write-Host "  Uncovered files: $uncoveredFiles"
        Write-Host ('  Overall percentage of coverage: {0:N2}%' -f $totalPercentage)
    }
}
finally
{
    if ($Coverage -and (Test-Path -LiteralPath $coverageReportPath))
    {
        Remove-Item -LiteralPath $coverageReportPath -Force
    }
}
