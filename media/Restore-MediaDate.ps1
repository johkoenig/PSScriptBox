<#
.SYNOPSIS
    Restores media dates and renames files using their best available date.

.DESCRIPTION
    Recursively processes supported media files in a folder. The date source
    priority is filename, EXIF DateTimeOriginal, CreateDate, then ModifyDate.
    Files are renamed when needed to YY-MM-DD HH-mm-ss XXXX with a random
    uppercase four-character code, and supported filesystem and embedded dates
    are set.

.PARAMETER InputPath
    Folder to search recursively. If omitted, the path is requested interactively.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.PARAMETER Confirm
Prompts before renaming a file or changing its dates.

.PARAMETER WhatIf
Previews proposed names and date updates without changing files.

.EXAMPLE
    .\Restore-MediaDate.ps1 -InputPath 'C:\Photos' -WhatIf
    Previews date sources and proposed filenames without changing files.

.EXAMPLE
    .\Restore-MediaDate.ps1 -InputPath 'C:\Photos'
    Processes supported media files without confirmation prompts.

.EXAMPLE
    .\Restore-MediaDate.ps1 -InputPath 'C:\Photos' -Confirm
    Prompts before each file is changed.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7 and ExifTool.
    ExifTool must be available in PATH. If it is missing, the script prints
    installation guidance. The script does not install software.
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
. (Join-Path $PSScriptRoot '..\common\internal\Get-MissingDependencyReport.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\ConvertTo-QuotedArgument.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-MediaTool.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-MediaDateInputFile.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-MediaDateSource.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-MediaDateUpdateArgument.ps1')
. (Join-Path $PSScriptRoot 'internal\New-MediaDateCode.ps1')
. (Join-Path $PSScriptRoot 'internal\New-MediaDateFileName.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-MediaDateRestoration.ps1')

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
    '     |  | MEDIA DATE RESTORATION              |  | |'
    '     |  | RENAME / RESET TAGS                 |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)
Write-Host ''
foreach ($headerLine in $headerLines)
{
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText 'Restores media dates from filenames and metadata.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Cyan
Write-Host (Get-LocalizedText 'Renames files to YY-MM-DD HH-mm-ss XXXX.ext.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Cyan
Write-Host ''

$missingDependencyTemplate = Get-LocalizedText -Text 'Missing dependency: {0}' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath
$exifToolCommand = Get-Command -Name 'exiftool.exe', 'exiftool' -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
if ($null -eq $exifToolCommand)
{
    $report = Get-MissingDependencyReport -Dependency 'ExifTool' `
        -Guidance (Get-LocalizedText 'Install ExifTool with Chocolatey: choco install exiftool -y, or download from https://exiftool.org/.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) `
        -MessageTemplate $missingDependencyTemplate
    Write-Host $report.Message -ForegroundColor Yellow
    Write-Host "  $( $report.Guidance )"
    exit 1
}

if ( [string]::IsNullOrWhiteSpace($InputPath))
{
    Write-Host (Get-LocalizedText 'Enter the folder containing media files to restore.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
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
    $inputSelection = Get-MediaDateInputFile -RootPath $InputPath `
        -UiLanguage $script:OutputLanguage -MessagesPath $script:MessagesPath
}
catch
{
    Write-Host (Get-LocalizedText -Text 'Error: {0}' -Arguments @($_.Exception.Message) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Red
    exit 1
}

$mediaFiles = @($inputSelection.Files)
$basePath = $inputSelection.BasePath
$basePathPrefix = $basePath
if (-not $basePathPrefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar))
{
    $basePathPrefix += [System.IO.Path]::DirectorySeparatorChar
}
$pathSegments = @($basePath.TrimEnd('\') -split '[\\/]' | Where-Object { $_ })
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
Write-Host (Get-LocalizedText '=== Media date restoration: processing started ===' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($basePath) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
Write-Host (Get-LocalizedText -Text 'Number of files: {0}' -Arguments @($mediaFiles.Count) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
Write-Host (Get-LocalizedText 'Date source priority: filename, EXIF DateTimeOriginal, CreateDate, ModifyDate' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
Write-Host (Get-LocalizedText 'Filename pattern: YY-MM-DD HH-mm-ss XXXX' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
Write-Host (Get-LocalizedText 'Creation time, last-write time, and supported metadata dates are changed only when needed.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)

if ($mediaFiles.Count -eq 0)
{
    Write-Host (Get-LocalizedText 'No supported media files found in the selected folder or its subfolders.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Yellow
}

$results = @()
for ($index = 0; $index -lt $mediaFiles.Count; $index++)
{
    $file = $mediaFiles[$index]
    $relativePath = $file.FullName.Substring($basePathPrefix.Length)
    Write-Host ''
    Write-Host (Get-LocalizedText -Text '--- Media file {0}/{1}: {2} ---' -Arguments @(
        ($index + 1), $mediaFiles.Count, $relativePath
    ) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Cyan

    $targetPath = $null
    try
    {
        $dateResult = Get-MediaDateSource -File $file -ExifToolPath $exifToolCommand.Source `
            -UiLanguage $script:OutputLanguage -MessagesPath $script:MessagesPath
        $alreadyFormatted = $dateResult.IsFileNameFormatted
        $targetName = if ($alreadyFormatted)
        {
            [pscustomobject]@{
                FileName = $file.Name
                FullPath = $file.FullName
            }
        }
        else
        {
            New-MediaDateFileName -DateTime $dateResult.DateTime `
                -DirectoryPath $file.DirectoryName -Extension $file.Extension `
                -UiLanguage $script:OutputLanguage -MessagesPath $script:MessagesPath
        }
        $targetPath = $targetName.FullPath

        Write-Host (Get-LocalizedText -Text 'Date source: {0}' -Arguments @(
            (Get-LocalizedText $dateResult.Source -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
        ) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
        Write-Host (Get-LocalizedText -Text 'Restored date: {0}' -Arguments @(
            $dateResult.DateTime.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
        ) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
        if ($alreadyFormatted)
        {
            Write-Host (Get-LocalizedText 'Filename already matches the requested pattern.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
            $action = Get-LocalizedText -Text 'Restore filesystem and metadata dates: {0}' -Arguments @($targetName.FileName) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath
        }
        else
        {
            Write-Host (Get-LocalizedText -Text 'Target filename: {0}' -Arguments @($targetName.FileName) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
            $action = Get-LocalizedText -Text 'Rename file and restore filesystem and metadata dates: {0}' -Arguments @($targetName.FileName) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath
        }

        if (-not $PSCmdlet.ShouldProcess($file.FullName, $action))
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
                FilePath = $file.FullName
                FailureReason = $skipReason
            }
            continue
        }

        $restoration = Invoke-MediaDateRestoration -File $file -TargetPath $targetName.FullPath `
            -DateTime $dateResult.DateTime -ExifToolPath $exifToolCommand.Source `
            -UiLanguage $script:OutputLanguage -MessagesPath $script:MessagesPath
        foreach ($warningMessage in $restoration.WarningMessages)
        {
            Write-Host $warningMessage -ForegroundColor Yellow
        }
        if ($alreadyFormatted)
        {
            Write-Host (Get-LocalizedText 'Filename kept unchanged.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Green
        }
        else
        {
            Write-Host (Get-LocalizedText -Text 'Renamed to: {0}' -Arguments @($targetName.FileName) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Green
        }
        Write-Host (Get-LocalizedText 'Filesystem and metadata dates were restored.' -Language $script:OutputLanguage -MessagesPath $script:MessagesPath) -ForegroundColor Green
        $results += [pscustomobject]@{
            Success = $true
            Skipped = $false
            FilePath = $restoration.FilePath
            FailureReason = $null
        }
    }
    catch
    {
        $failureReason = $_.Exception.Message
        $failurePath = if ($targetPath -and -not (Test-Path -LiteralPath $file.FullName) -and
                (Test-Path -LiteralPath $targetPath))
        {
            $targetPath
        }
        else
        {
            $file.FullName
        }
        Write-Warning (Get-LocalizedText -Text "Could not restore '{0}':`n{1}" -Arguments @(
            $file.Name, $failureReason
        ) -Language $script:OutputLanguage -MessagesPath $script:MessagesPath)
        $results += [pscustomobject]@{
            Success = $false
            Skipped = $false
            FilePath = $failurePath
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
