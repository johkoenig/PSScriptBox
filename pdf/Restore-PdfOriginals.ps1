<#
.SYNOPSIS
    Restores original PDFs from backups and removes the processed PDFs.

.DESCRIPTION
    Recursively searches a folder for _orig PDF backups with a matching
    processed PDF. For each approved item, the processed PDF is atomically
    replaced by the original backup, removing the _orig file. Use -WhatIf to
    preview the restore list.

.PARAMETER InputPath
    Folder to search recursively. If omitted, the path is requested interactively.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.EXAMPLE
    .\Restore-PdfOriginals.ps1
    Prompts for a folder.

.EXAMPLE
    .\Restore-PdfOriginals.ps1 -InputPath 'C:\PDFs' -WhatIf
    Previews which processed PDFs would be replaced by their original backups.

.EXAMPLE
    .\Restore-PdfOriginals.ps1 -InputPath 'C:\PDFs' -Confirm:$false
    Restores all matching original PDFs without per-file confirmation.

.NOTES
    Dependencies: PowerShell 5.1 or later. No additional programs or modules
    are required.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string] $InputPath,

    [switch] $EnglishOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\common\internal\Get-LocalizedText.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-EligibleOriginalPdf.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-OriginalPdfRestore.ps1')

$script:OutputLanguage = if (
$EnglishOutput -or [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'de'
)
{
    'en'
}
else
{
    'de'
}
$script:GermanMessages = if ($script:OutputLanguage -eq 'de')
{
    Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1')
}
else
{
    @{ }
}

$headerLines = @(
    '       .-------------------------------------------.'
    '      /                                           /|'
    '     /___________________________________________/ |'
    '     |  .-------------------------------------.  | |'
    '     |  | PDF ORIGINAL RESTORE                |  | |'
    '     |  | REMOVE PROCESSED / RESTORE _ORIG    |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)

Write-Host ''
foreach ($headerLine in $headerLines)
{
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText 'Restores original PDFs and removes processed PDFs.') -ForegroundColor Cyan
Write-Host ''

if ( [string]::IsNullOrWhiteSpace($InputPath))
{
    Write-Host (Get-LocalizedText 'Enter the folder containing processed PDF files.')
    $InputPath = Read-Host -Prompt (Get-LocalizedText 'InputPath')
}
if ( [string]::IsNullOrWhiteSpace($InputPath))
{
    throw (Get-LocalizedText 'No folder was specified.')
}

$InputPath = [Environment]::ExpandEnvironmentVariables($InputPath.Trim().Trim('"'))
if (-not (Test-Path -LiteralPath $InputPath -PathType Container))
{
    throw (Get-LocalizedText -Text 'The specified folder was not found: {0}' -Arguments @($InputPath))
}

$directory = Get-Item -LiteralPath $InputPath
$basePathPrefix = $directory.FullName
if (-not $basePathPrefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar))
{
    $basePathPrefix += [System.IO.Path]::DirectorySeparatorChar
}
$pathSegments = @($directory.FullName.TrimEnd('\') -split '[\\/]' | Where-Object { $_ })
$pathTail = @($pathSegments | Select-Object -Last 3)
$summaryPath = if ($pathTail.Count -gt 0)
{
    '.\' + ($pathTail -join '\') + '\'
}
else
{
    '.\'
}
$eligibleFiles = @(Get-EligibleOriginalPdf -RootPath $directory.FullName)
$eligibleCount = $eligibleFiles.Count
$restoredCount = 0
$failedFiles = @()

Write-Host (Get-LocalizedText -Text '  Folder: {0}' -Arguments @($directory.FullName))
Write-Host (Get-LocalizedText -Text '  PDF pairs eligible for restoration: {0}' -Arguments @($eligibleCount)) -ForegroundColor Yellow

if ($eligibleCount -eq 0)
{
    Write-Host (Get-LocalizedText 'No matching _orig PDFs with a processed PDF were found.') -ForegroundColor Green
    Write-Host ''
    Write-Host (Get-LocalizedText '=== Summary ===') -ForegroundColor Cyan
    Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath))
    Write-Host (Get-LocalizedText 'Found: 0')
    Write-Host (Get-LocalizedText 'Restored: 0')
    Write-Host (Get-LocalizedText 'Failed: 0')
    return
}

Write-Host ''
foreach ($originalFile in $eligibleFiles)
{
    $processedBaseName = $originalFile.BaseName -replace '_orig$', ''
    $processedPath = Join-Path -Path $originalFile.DirectoryName -ChildPath ($processedBaseName + $originalFile.Extension)
    $relativeProcessedPath = $processedPath.Substring($basePathPrefix.Length)
    Write-Host "  - $relativeProcessedPath"
}

if ($WhatIfPreference)
{
    Write-Host ''
    Write-Host (Get-LocalizedText 'Preview: no files were changed.') -ForegroundColor Cyan
    Write-Host ''
    Write-Host (Get-LocalizedText '=== Summary ===') -ForegroundColor Cyan
    Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath))
    Write-Host (Get-LocalizedText -Text 'Found: {0}' -Arguments @($eligibleCount))
    Write-Host (Get-LocalizedText 'Restored: 0')
    Write-Host (Get-LocalizedText 'Failed: 0')
    return
}

$approvedFiles = @(
foreach ($originalFile in $eligibleFiles)
{
    $processedBaseName = $originalFile.BaseName -replace '_orig$', ''
    $processedPath = Join-Path -Path $originalFile.DirectoryName -ChildPath ($processedBaseName + $originalFile.Extension)
    $relativeProcessedPath = $processedPath.Substring($basePathPrefix.Length)
    $action = Get-LocalizedText -Text 'Restore original PDF and remove processed PDF: {0}' -Arguments @($relativeProcessedPath)
    if ( $PSCmdlet.ShouldProcess($relativeProcessedPath, $action))
    {
        $originalFile
    }
}
)

if ($approvedFiles.Count -gt 0)
{
    Write-Host ''
    Write-Host (Get-LocalizedText 'Restoring original PDFs...') -ForegroundColor Cyan
}

foreach ($originalFile in $approvedFiles)
{
    $relativeOriginalPath = $originalFile.FullName.Substring($basePathPrefix.Length)
    $result = Invoke-OriginalPdfRestore -OriginalFile $originalFile
    if ($result.Success)
    {
        Write-Host (Get-LocalizedText -Text '  Restored: {0}' -Arguments @($result.ProcessedPath.Substring($basePathPrefix.Length))) -ForegroundColor Green
        $restoredCount++
    }
    else
    {
        $failedFiles += [pscustomobject]@{
            Path = $relativeOriginalPath
            Reason = $result.Error
        }
        Write-Warning (Get-LocalizedText -Text "Could not restore '{0}': {1}" -Arguments @($relativeOriginalPath, $result.Error))
    }
}

Write-Host ''
Write-Host (Get-LocalizedText '=== Summary ===') -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath))
Write-Host (Get-LocalizedText -Text 'Found: {0}' -Arguments @($eligibleCount))
Write-Host (Get-LocalizedText -Text 'Restored: {0}' -Arguments @($restoredCount))
Write-Host (Get-LocalizedText -Text 'Failed: {0}' -Arguments @($failedFiles.Count))
if ($failedFiles.Count -gt 0)
{
    Write-Host (Get-LocalizedText 'PDFs that could not be restored:') -ForegroundColor DarkYellow
    foreach ($failedFile in $failedFiles)
    {
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($failedFile.Path, $failedFile.Reason)) -ForegroundColor DarkYellow
    }
}
