<#
.SYNOPSIS
    Removes Live Photo videos while keeping their matching still images.

.DESCRIPTION
    Recursively finds MOV files with a same-name JPG image in the same folder
    and removes the MOV video. Use -WhatIf to preview candidates before
    deletion.

.PARAMETER InputPath
    Folder to search recursively. If omitted, the path is requested interactively.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.PARAMETER Confirm
Prompts before deleting each matching MOV file.

.PARAMETER WhatIf
Shows matching MOV files without deleting them.

.EXAMPLE
    .\Remove-LivePhotos.ps1 -InputPath 'C:\Photos' -WhatIf
    Previews MOV files that have a same-name JPG in the same folder.

.EXAMPLE
    .\Remove-LivePhotos.ps1 -InputPath 'C:\Photos'
    Removes matching MOV files without prompting.

.EXAMPLE
    .\Remove-LivePhotos.ps1 -InputPath 'C:\Photos' -Confirm
    Prompts before deleting each matching MOV file.

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
. (Join-Path $PSScriptRoot 'internal\Get-LivePhotoVideoCandidate.ps1')

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
$script:MessagesPath = Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1'

$headerLines = @(
    '       .-------------------------------------------.'
    '      /                                           /|'
    '     /___________________________________________/ |'
    '     |  .-------------------------------------.  | |'
    '     |  | LIVE PHOTO VIDEO CLEANUP            |  | |'
    '     |  | KEEP JPG / REMOVE MOV               |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)

Write-Host ''
foreach ($headerLine in $headerLines)
{
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText 'Removes MOV videos paired with same-name JPG still images.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Cyan
Write-Host (Get-LocalizedText 'Matching still images are kept; use -WhatIf to preview deletions.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Cyan
Write-Host ''

if ( [string]::IsNullOrWhiteSpace($InputPath))
{
    Write-Host (Get-LocalizedText 'Enter the folder containing Live Photo files.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
    Write-Host (Get-LocalizedText 'Press Ctrl+C to cancel input.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Yellow
    $InputPath = Read-Host -Prompt (Get-LocalizedText 'InputPath' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
}
if ( [string]::IsNullOrWhiteSpace($InputPath))
{
    Write-Host (Get-LocalizedText 'No folder was specified.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Red
    exit 1
}

$InputPath = [Environment]::ExpandEnvironmentVariables($InputPath.Trim().Trim('"'))
try
{
    if (-not (Test-Path -LiteralPath $InputPath -PathType Container))
    {
        throw (Get-LocalizedText -Text 'The specified folder was not found: {0}' -Arguments @($InputPath) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
    }

    $directory = Get-Item -LiteralPath $InputPath -ErrorAction Stop
    $candidates = @(Get-LivePhotoVideoCandidate -RootPath $directory.FullName)
}
catch
{
    Write-Host (Get-LocalizedText -Text 'Error: {0}' -Arguments @($_.Exception.Message) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Red
    exit 1
}

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

Write-Host ''
Write-Host (Get-LocalizedText '=== Live Photo removal: processing started ===' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($directory.FullName) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
Write-Host (Get-LocalizedText -Text 'Matching MOV videos: {0}' -Arguments @($candidates.Count) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)

if ($candidates.Count -eq 0)
{
    Write-Host (Get-LocalizedText 'No MOV videos with a same-name JPG still image were found.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Green
}

$results = @()
for ($index = 0; $index -lt $candidates.Count; $index++)
{
    $candidate = $candidates[$index]
    $relativePath = $candidate.VideoFile.FullName.Substring($basePathPrefix.Length)
    Write-Host ''
    Write-Host (Get-LocalizedText -Text '--- Live Photo {0}/{1}: {2} ---' -Arguments @(
        ($index + 1), $candidates.Count, $relativePath
    ) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Cyan
    Write-Host (Get-LocalizedText -Text 'Matching still image kept: {0}' -Arguments @(
        $candidate.PhotoFile.Name
    ) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)

    $action = Get-LocalizedText -Text 'Delete Live Photo video and keep still image: {0}' -Arguments @(
        $candidate.VideoFile.Name
    ) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath
    if (-not $PSCmdlet.ShouldProcess($candidate.VideoFile.FullName, $action))
    {
        $skipReason = if ($WhatIfPreference)
        {
            Get-LocalizedText 'Preview only; no files were changed.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath
        }
        else
        {
            Get-LocalizedText 'Operation was not approved.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath
        }
        $results += [pscustomobject]@{
            Success = $false
            Skipped = $true
            FilePath = $candidate.VideoFile.FullName
            FailureReason = $skipReason
        }
        continue
    }

    try
    {
        Remove-Item -LiteralPath $candidate.VideoFile.FullName -Force -ErrorAction Stop
        Write-Host (Get-LocalizedText -Text 'Deleted: {0}' -Arguments @($relativePath) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Green
        $results += [pscustomobject]@{
            Success = $true
            Skipped = $false
            FilePath = $candidate.VideoFile.FullName
            FailureReason = $null
        }
    }
    catch
    {
        $failureReason = $_.Exception.Message
        Write-Warning (Get-LocalizedText -Text "Could not delete '{0}':`n{1}" -Arguments @(
            $relativePath, $failureReason
        ) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
        $results += [pscustomobject]@{
            Success = $false
            Skipped = $false
            FilePath = $candidate.VideoFile.FullName
            FailureReason = $failureReason
        }
    }
}

$successfulResults = @($results | Where-Object { $_.Success })
$skippedResults = @($results | Where-Object { $_.Skipped })
$failedResults = @($results | Where-Object { -not $_.Success -and -not $_.Skipped })

Write-Host ''
Write-Host (Get-LocalizedText '=== Summary ===' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
Write-Host (Get-LocalizedText -Text 'Succeeded: {0}, skipped: {1}, failed: {2}' -Arguments @(
    $successfulResults.Count, $skippedResults.Count, $failedResults.Count
) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
Write-Host ''
Write-Host (Get-LocalizedText 'Failed files:' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Cyan
if ($failedResults.Count -eq 0)
{
    Write-Host (Get-LocalizedText '  None.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
}
else
{
    foreach ($result in $failedResults)
    {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @(
            $relativePath, $result.FailureReason
        ) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Yellow
    }
}
Write-Host ''
Write-Host (Get-LocalizedText 'Skipped files:' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Cyan
if ($skippedResults.Count -eq 0)
{
    Write-Host (Get-LocalizedText '  None.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
}
else
{
    foreach ($result in $skippedResults)
    {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @(
            $relativePath, $result.FailureReason
        ) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor DarkYellow
    }
}
