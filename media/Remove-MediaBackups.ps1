<#
.SYNOPSIS
    Removes media backups when the processed media file exists.

.DESCRIPTION
    Recursively searches a folder for MOV, MP4, JPG, and JPEG files with the
    _orig suffix before the extension. A backup is eligible only when its
    processed counterpart exists in the same folder. MOV backups match MP4
    outputs; other supported backups match the same extension. Use -WhatIf to
    preview the deletion list safely.

.PARAMETER InputPath
    Folder to search recursively for matching _orig media backups. If omitted,
    the path is requested interactively.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.PARAMETER Confirm
Prompts before deleting each eligible backup.

.PARAMETER WhatIf
Shows eligible backups without deleting them.

.EXAMPLE
    .\Remove-MediaBackups.ps1
    Prompts for a folder.

.EXAMPLE
    .\Remove-MediaBackups.ps1 -InputPath 'C:\Media' -WhatIf
    Previews which _orig files would be deleted.

.EXAMPLE
    .\Remove-MediaBackups.ps1 -InputPath 'C:\Media'
    Removes eligible backups without prompting.

.EXAMPLE
    .\Remove-MediaBackups.ps1 -InputPath 'C:\Media' -Confirm
    Prompts before deleting each eligible backup.

.NOTES
    Dependencies: PowerShell 5.1 or later. No additional programs or modules
    are required.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
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
. (Join-Path $PSScriptRoot 'internal\Get-EligibleMediaBackup.ps1')

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
    '     |  | MEDIA BACKUP CLEANUP                |  | |'
    '     |  | VERIFY / REMOVE _ORIG               |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)

Write-Host ''
foreach ($headerLine in $headerLines)
{
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText 'Removes eligible original media backups.') -ForegroundColor Cyan
Write-Host ''

if ( [string]::IsNullOrWhiteSpace($InputPath))
{
    Write-Host (Get-LocalizedText 'Enter the folder containing original media backups.')
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
$eligibleBackups = @(Get-EligibleMediaBackup -RootPath $directory.FullName)
$eligibleCount = $eligibleBackups.Count
$deletedCount = 0

Write-Host (Get-LocalizedText -Text '  Folder: {0}' -Arguments @($directory.FullName))
Write-Host (Get-LocalizedText -Text '  Original media backups eligible for deletion: {0}' -Arguments @($eligibleCount)) -ForegroundColor Yellow

if ($eligibleCount -eq 0)
{
    Write-Host (Get-LocalizedText 'No matching _orig media backups with a processed media file were found.') -ForegroundColor Green
    Write-Host ''
    Write-Host (Get-LocalizedText '=== Summary ===') -ForegroundColor Cyan
    Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath))
    Write-Host (Get-LocalizedText 'Found: 0')
    Write-Host (Get-LocalizedText 'Deleted: 0')
    return
}

Write-Host ''
foreach ($backup in $eligibleBackups)
{
    $relativePath = $backup.BackupFile.FullName.Substring($basePathPrefix.Length)
    Write-Host "  - $relativePath"
}

if ($WhatIfPreference)
{
    Write-Host ''
    Write-Host (Get-LocalizedText 'Preview: no files were deleted.') -ForegroundColor Cyan
    Write-Host ''
    Write-Host (Get-LocalizedText '=== Summary ===') -ForegroundColor Cyan
    Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath))
    Write-Host (Get-LocalizedText -Text 'Found: {0}' -Arguments @($eligibleCount))
    Write-Host (Get-LocalizedText 'Deleted: 0')
    return
}

$approvedBackups = @(
foreach ($backup in $eligibleBackups)
{
    $relativePath = $backup.BackupFile.FullName.Substring($basePathPrefix.Length)
    $relativeProcessedPath = $backup.ProcessedPath.Substring($basePathPrefix.Length)
    $action = Get-LocalizedText -Text 'Delete original media backup; keep processed media file: {0}' -Arguments @($relativeProcessedPath)
    if ( $PSCmdlet.ShouldProcess($relativePath, $action))
    {
        $backup
    }
}
)

if ($approvedBackups.Count -gt 0)
{
    Write-Host ''
    Write-Host (Get-LocalizedText 'Deleting original media backups...') -ForegroundColor Cyan
}

foreach ($backup in $approvedBackups)
{
    $relativePath = $backup.BackupFile.FullName.Substring($basePathPrefix.Length)
    Remove-Item -LiteralPath $backup.BackupFile.FullName -Force
    Write-Host (Get-LocalizedText -Text '  Deleted: {0}' -Arguments @($relativePath)) -ForegroundColor Green
    $deletedCount++
}

Write-Host ''
Write-Host (Get-LocalizedText '=== Summary ===') -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath))
Write-Host (Get-LocalizedText -Text 'Found: {0}' -Arguments @($eligibleCount))
Write-Host (Get-LocalizedText -Text 'Deleted: {0}' -Arguments @($deletedCount))
