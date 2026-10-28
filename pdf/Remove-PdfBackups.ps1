<#
.SYNOPSIS
    Removes PDF backups when the processed PDF exists.

.DESCRIPTION
    Recursively searches a folder for PDF files with the _orig suffix before the
    extension. A backup is deleted only when the corresponding processed PDF
    without the _orig suffix exists in the same folder. Use -WhatIf to preview
    the deletion list safely.

.PARAMETER InputPath
    Folder to search recursively for matching _orig PDFs. If omitted, the path
    is requested interactively.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.PARAMETER Confirm
Prompts before deleting each eligible backup.

.PARAMETER WhatIf
Shows eligible backups without deleting them.

.EXAMPLE
    .\Remove-PdfBackups.ps1
    Prompts for a folder.

.EXAMPLE
    .\Remove-PdfBackups.ps1 -InputPath 'C:\PDFs' -WhatIf
    Previews which _orig files would be deleted.

.EXAMPLE
    .\Remove-PdfBackups.ps1 -InputPath 'C:\PDFs'
    Removes eligible backups without prompting.

.EXAMPLE
    .\Remove-PdfBackups.ps1 -InputPath 'C:\PDFs' -Confirm
    Prompts before deleting each eligible backup.

.NOTES
    Dependencies: PowerShell 5.1 or later. No additional programs or modules
    are required.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'This user-facing script provides localized, color-coded console output.'
)]
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string] $InputPath,

    [switch] $EnglishOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\common\internal\Get-LocalizedText.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-EligibleOriginalPdf.ps1')

$OutputLanguage = if (
    $EnglishOutput -or [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'de'
) { 'en' } else { 'de' }
$MessagesPath = Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1'

$headerLines = @(
    '       .-------------------------------------------.'
    '      /                                           /|'
    '     /___________________________________________/ |'
    '     |  .-------------------------------------.  | |'
    '     |  | PDF BACKUP CLEANUP                  |  | |'
    '     |  | VERIFY / REMOVE _ORIG               |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)

Write-Host ''
foreach ($headerLine in $headerLines) {
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText 'Removes eligible original PDF backups.' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
Write-Host ''

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    Write-Host (Get-LocalizedText 'Enter the folder containing original PDF backups.' -Language $OutputLanguage -MessagesPath $MessagesPath)
    $InputPath = Read-Host -Prompt (Get-LocalizedText 'InputPath' -Language $OutputLanguage -MessagesPath $MessagesPath)
}
if ([string]::IsNullOrWhiteSpace($InputPath)) {
    throw (Get-LocalizedText 'No folder was specified.' -Language $OutputLanguage -MessagesPath $MessagesPath)
}

$InputPath = [Environment]::ExpandEnvironmentVariables($InputPath.Trim().Trim('"'))
if (-not (Test-Path -LiteralPath $InputPath -PathType Container)) {
    throw (Get-LocalizedText -Text 'The specified folder was not found: {0}' -Arguments @($InputPath) -Language $OutputLanguage -MessagesPath $MessagesPath)
}

$directory = Get-Item -LiteralPath $InputPath
$basePathPrefix = $directory.FullName
if (-not $basePathPrefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar)) {
    $basePathPrefix += [System.IO.Path]::DirectorySeparatorChar
}
$pathSegments = @($directory.FullName.TrimEnd('\') -split '[\\/]' | Where-Object { $_ })
$pathTail = @($pathSegments | Select-Object -Last 3)
$summaryPath = if ($pathTail.Count -gt 0) { '.\' + ($pathTail -join '\') + '\' } else { '.\' }
$eligibleFiles = @(Get-EligibleOriginalPdf -RootPath $directory.FullName)
$eligibleCount = $eligibleFiles.Count
$deletedCount = 0

Write-Host (Get-LocalizedText -Text '  Folder: {0}' -Arguments @($directory.FullName) -Language $OutputLanguage -MessagesPath $MessagesPath)
Write-Host (Get-LocalizedText -Text '  Original PDF backups eligible for deletion: {0}' -Arguments @($eligibleCount) -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Yellow

if ($eligibleCount -eq 0) {
    Write-Host (Get-LocalizedText 'No matching _orig PDFs with a processed PDF were found.' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Green
    Write-Host ''
    Write-Host (Get-LocalizedText '=== Summary ===' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
    Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath) -Language $OutputLanguage -MessagesPath $MessagesPath)
    Write-Host (Get-LocalizedText 'Found: 0' -Language $OutputLanguage -MessagesPath $MessagesPath)
    Write-Host (Get-LocalizedText 'Deleted: 0' -Language $OutputLanguage -MessagesPath $MessagesPath)
    return
}

Write-Host ''
foreach ($originalFile in $eligibleFiles) {
    $relativePath = $originalFile.FullName.Substring($basePathPrefix.Length)
    Write-Host "  - $relativePath"
}

if ($WhatIfPreference) {
    Write-Host ''
    Write-Host (Get-LocalizedText 'Preview: no files were deleted.' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
    Write-Host ''
    Write-Host (Get-LocalizedText '=== Summary ===' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
    Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath) -Language $OutputLanguage -MessagesPath $MessagesPath)
    Write-Host (Get-LocalizedText -Text 'Found: {0}' -Arguments @($eligibleCount) -Language $OutputLanguage -MessagesPath $MessagesPath)
    Write-Host (Get-LocalizedText 'Deleted: 0' -Language $OutputLanguage -MessagesPath $MessagesPath)
    return
}

$approvedFiles = @(
    foreach ($originalFile in $eligibleFiles) {
        $processedBaseName = $originalFile.BaseName -replace '_orig$', ''
        $processedPath = Join-Path -Path $originalFile.DirectoryName -ChildPath ($processedBaseName + $originalFile.Extension)
        $relativePath = $originalFile.FullName.Substring($basePathPrefix.Length)
        $relativeProcessedPath = $processedPath.Substring($basePathPrefix.Length)
        $action = Get-LocalizedText -Text 'Delete original PDF backup; keep processed PDF: {0}' -Arguments @($relativeProcessedPath) -Language $OutputLanguage -MessagesPath $MessagesPath
        if ($PSCmdlet.ShouldProcess($relativePath, $action)) {
            $originalFile
        }
    }
)

if ($approvedFiles.Count -gt 0) {
    Write-Host ''
    Write-Host (Get-LocalizedText 'Deleting original PDF backups...' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
}

foreach ($originalFile in $approvedFiles) {
    $relativePath = $originalFile.FullName.Substring($basePathPrefix.Length)
    Remove-Item -LiteralPath $originalFile.FullName -Force
    Write-Host (Get-LocalizedText -Text '  Deleted: {0}' -Arguments @($relativePath) -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Green
    $deletedCount++
}

Write-Host ''
Write-Host (Get-LocalizedText '=== Summary ===' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath) -Language $OutputLanguage -MessagesPath $MessagesPath)
Write-Host (Get-LocalizedText -Text 'Found: {0}' -Arguments @($eligibleCount) -Language $OutputLanguage -MessagesPath $MessagesPath)
Write-Host (Get-LocalizedText -Text 'Deleted: {0}' -Arguments @($deletedCount) -Language $OutputLanguage -MessagesPath $MessagesPath)
