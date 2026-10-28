<#
.SYNOPSIS
    Reduces PDF file sizes by downsampling images.

.DESCRIPTION
    Processes one PDF file or all PDF files in a specified folder and its
    subfolders. Ghostscript downsamples color, grayscale, and monochrome images
    and encodes color and grayscale images as JPEG. Digitally signed and
    encrypted PDFs cannot be processed and are reported as issues.
    The input is replaced only when the optimized output is smaller.

    By default, files smaller than 1 MB are skipped, and images are downsampled
    to 300 DPI at JPEG quality 75. On success, the input file is replaced. By
    default, the original is saved as <Name>_orig.pdf. If that backup already
    exists, it is preserved and the input is replaced directly.
    -ReplaceOriginal replaces the input without a backup.
    For folder input, all PDFs are discovered first and files below the
    minimum size are excluded before the processing loop.
    The summary counts routine skips without listing them; encrypted and signed
    PDFs are reported among the files with issues.

    The script does not require administrator rights or install software.
    Missing dependencies are reported with installation instructions.

.PARAMETER InputPath
    Optional path to a PDF file or folder containing PDFs. If omitted, the path
    is requested interactively.

.PARAMETER Dpi
    Target image resolution for Ghostscript downsampling (50-1200). Default: 300.

.PARAMETER JpegQuality
    JPEG quality for downsampled images (1-100). Default: 75.

.PARAMETER MinFileSize
    Minimum original file size in bytes for processing. PowerShell size literals
    such as 2MB can be used. Default: 1MB. Use 0 to disable the threshold.

.PARAMETER ReplaceOriginal
    Replaces the input without a backup. By default, the original is saved as
    <Name>_orig.pdf. An existing backup is preserved.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.EXAMPLE
    .\Optimize-PdfSize.ps1
    Starts interactively, skips files smaller than 1 MB, and targets 300 DPI
    with JPEG quality 75.

.EXAMPLE
    .\Optimize-PdfSize.ps1 -InputPath 'C:\PDFs' -Dpi 200 -JpegQuality 65 -MinFileSize 2MB
    Optimizes PDFs of at least 2 MB in C:\PDFs with a 200 DPI target and JPEG quality 65.

.EXAMPLE
    .\Optimize-PdfSize.ps1 -InputPath 'C:\PDFs' -ReplaceOriginal
    Replaces smaller optimized PDFs in C:\PDFs without creating backups.

.NOTES
    Dependencies:
      - Python
      - pikepdf (used to detect encryption and digital signatures)
      - Ghostscript

    Use .\Initialize-PdfProcessor.ps1 to check and install the required software.
    The output is a standard PDF version 1.5, not a PDF/A archive.
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
[CmdletBinding()]
param(
# Optional path to a PDF file or a folder containing PDFs.
    [string] $InputPath,

# Target image resolution for Ghostscript downsampling. Default: 300 DPI.
    [ValidateRange(50, 1200)]
    [int] $Dpi = 300,

# JPEG quality for downsampled images. Default: 75.
    [ValidateRange(1, 100)]
    [int] $JpegQuality = 75,

# Minimum original PDF size in bytes; PowerShell size literals such as 2MB work.
    [ValidateScript({ $_ -ge 0 })]
    [long] $MinFileSize = 1MB,

# Replace the input without creating an _orig backup.
    [switch] $ReplaceOriginal,

# Force English console output regardless of the Windows display language.
    [switch] $EnglishOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'internal\Get-PdfPythonRuntime.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-LocalizedText.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-ExecutablePath.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-GhostscriptExecutablePath.ps1')
. (Join-Path $PSScriptRoot 'internal\Test-PythonModule.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-PdfInputFile.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\ConvertTo-QuotedArgument.ps1')
. (Join-Path $PSScriptRoot 'internal\Optimize-WithGhostscript.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-PdfSizeOptimization.ps1')

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
    '     |  | PDF SIZE OPTIMIZATION               |  | |'
    '     |  | DOWNSAMPLE / JPEG                   |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)
Write-Host ''
foreach ($headerLine in $headerLines)
{
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText '  Reduces PDF size by downsampling images.') -ForegroundColor Cyan
if (-not $ReplaceOriginal)
{
    Write-Host (Get-LocalizedText '  Originals are saved as _orig files.') -ForegroundColor Cyan
}
else
{
    Write-Host (Get-LocalizedText '  Originals are replaced without a backup.') -ForegroundColor Cyan
}
Write-Host ''

$pythonRuntime = Get-PdfPythonRuntime
$ghostscriptPath = Get-GhostscriptExecutablePath
$missing = [System.Collections.Generic.List[string]]::new()
if (-not $pythonRuntime)
{
    $missing.Add((Get-LocalizedText 'Python (py.exe or python.exe)'))
}
elseif (-not (Test-PythonModule -PythonPath $pythonRuntime.Path -ModuleName 'pikepdf'))
{
    $missing.Add((Get-LocalizedText 'pikepdf (Python module)'))
}
if (-not $ghostscriptPath)
{
    $missing.Add((Get-LocalizedText 'Ghostscript'))
}
if ($missing.Count -gt 0)
{
    Write-Host "`n$( Get-LocalizedText 'Missing dependencies:' )" -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "  - $_" }
    Write-Host "`n$( Get-LocalizedText 'Run Initialize-PdfProcessor.ps1 to install the missing dependencies.' )"
    exit 1
}

try
{
    $selectedPath = $InputPath
    if ( [string]::IsNullOrWhiteSpace($selectedPath))
    {
        Write-Host ''
        Write-Host (Get-LocalizedText 'Available parameters:') -ForegroundColor Cyan
        Write-Host (Get-LocalizedText '  -InputPath <path>       PDF file or folder; prompts if omitted.')
        Write-Host (Get-LocalizedText '  -Dpi <50-1200>          Target image resolution (default: 300).')
        Write-Host (Get-LocalizedText '  -JpegQuality <1-100>   JPEG quality (default: 75).')
        Write-Host (Get-LocalizedText '  -MinFileSize <size>    Minimum original size (default: 1 MB; use 0 to disable).')
        Write-Host (Get-LocalizedText '  -ReplaceOriginal       Replace original without an _orig backup.')
        Write-Host (Get-LocalizedText '  -EnglishOutput         Force English console output.')
        Write-Host (Get-LocalizedText 'Press Ctrl+C to cancel input.') -ForegroundColor Yellow
        $selectedPath = Read-Host -Prompt (Get-LocalizedText 'Path to a PDF file or a folder containing PDFs')
    }
    $resolvedSelectedPath = [Environment]::ExpandEnvironmentVariables(([string]$selectedPath).Trim().Trim('"'))
    $inputSelection = Get-PdfInputFile -Path $resolvedSelectedPath -UiLanguage $script:OutputLanguage -Messages $script:GermanMessages
    $folderInput = Test-Path -LiteralPath $resolvedSelectedPath -PathType Container
}
catch
{
    Write-Error $_.Exception.Message
    exit 1
}

$allPdfFiles = @($inputSelection.Files)
if ($allPdfFiles.Count -eq 0)
{
    Write-Host (Get-LocalizedText 'No PDFs found.')
    exit 0
}
$pdfFiles = $allPdfFiles
$belowMinimumCount = 0
if ($folderInput)
{
    $pdfFiles = @($allPdfFiles | Where-Object { $_.Length -ge $MinFileSize })
    $belowMinimumCount = $allPdfFiles.Count - $pdfFiles.Count
}
$inputBasePath = $inputSelection.BasePath
$summaryPathSegments = @($inputBasePath.TrimEnd('\') -split '[\\/]' | Where-Object { $_ })
$summaryPath = '.\' + ((@($summaryPathSegments | Select-Object -Last 3)) -join '\') + '\'
$basePathPrefix = $inputBasePath
if (-not $basePathPrefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar))
{
    $basePathPrefix += [System.IO.Path]::DirectorySeparatorChar
}

Write-Host ''
Write-Host (Get-LocalizedText '=== PDF size optimization: processing started ===') -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Number of files: {0}' -Arguments @($allPdfFiles.Count))
if ($folderInput)
{
    Write-Host (Get-LocalizedText -Text 'Files to process: {0}' -Arguments @($pdfFiles.Count))
}
Write-Host (Get-LocalizedText -Text 'Ghostscript DPI: {0}' -Arguments @($Dpi))
Write-Host (Get-LocalizedText -Text 'JPEG quality: {0}' -Arguments @($JpegQuality))
Write-Host (Get-LocalizedText -Text 'Minimum file size: {0:N2} MB' -Arguments @(($MinFileSize / 1MB)))
Write-Host (Get-LocalizedText 'Output format: standard PDF (version 1.5)')

$reporter = {
    param($Kind, $Color, $Text)
    if ($Kind -eq 'Warning')
    {
        Write-Warning $Text; return
    }
    if ($Color)
    {
        Write-Host $Text -ForegroundColor $Color
    }
    else
    {
        Write-Host $Text
    }
}
$results = @()
for ($i = 0; $i -lt $pdfFiles.Count; $i++) {
    $pdf = $pdfFiles[$i]
    Write-Host ''
    Write-Host (Get-LocalizedText -Text '--- File {0}/{1}: {2} ---' -Arguments @(($i + 1), $pdfFiles.Count, $pdf.Name)) -ForegroundColor Cyan
    $result = Invoke-PdfSizeOptimization -Pdf $pdf -PythonPath $pythonRuntime.Path `
        -GhostscriptPath $ghostscriptPath -Dpi $Dpi -Quality $JpegQuality -MinFileSize $MinFileSize `
        -ReplaceOriginal $ReplaceOriginal.IsPresent -UiLanguage $script:OutputLanguage `
        -Messages $script:GermanMessages -Reporter $reporter
    if ($null -ne $result)
    {
        $results += $result
    }
}

$successResults = @($results | Where-Object { $_.Success })
$skippedResults = @($results | Where-Object { $_.Skipped })
$failedResults = @($results | Where-Object { -not $_.Success -and -not $_.Skipped })
$warningResults = @($results | Where-Object { $_.Warning })
$successCount = $successResults.Count
$skippedCount = $belowMinimumCount + $skippedResults.Count
$failureCount = $failedResults.Count
$sumOriginal = [long](($results | ForEach-Object { [long]$_.OriginalBytes }) | Measure-Object -Sum).Sum
$sumResult = [long](($successResults | ForEach-Object { [long]$_.ResultBytes }) | Measure-Object -Sum).Sum
$savedMb = ($sumOriginal - $sumResult) / 1MB
$savedPct = if ($sumOriginal -gt 0)
{
    (1 - ($sumResult / $sumOriginal)) * 100
}
else
{
    0
}

Write-Host ''
Write-Host (Get-LocalizedText '=== Summary ===') -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath))
Write-Host (Get-LocalizedText -Text 'Succeeded: {0}, skipped: {1}, failed: {2}' -Arguments @($successCount, $skippedCount, $failureCount))
if ($successCount -gt 0)
{
    Write-Host (Get-LocalizedText -Text 'Original total: {0:N2} MB' -Arguments @(($sumOriginal / 1MB)))
    Write-Host (Get-LocalizedText -Text 'Result total: {0:N2} MB' -Arguments @(($sumResult / 1MB)))
    Write-Host (Get-LocalizedText -Text 'Total saved: {0:N2} MB ({1:N1}%)' -Arguments @($savedMb, $savedPct))
}
if (-not $ReplaceOriginal)
{
    Write-Host (Get-LocalizedText 'Originals are saved as _orig files; existing backups are preserved.')
}
else
{
    Write-Host (Get-LocalizedText 'Originals were replaced.')
}
Write-Host ''
Write-Host (Get-LocalizedText 'Failed files:') -ForegroundColor Cyan
if ($failedResults.Count -eq 0)
{
    Write-Host (Get-LocalizedText '  None.')
}
else
{
    foreach ($failedFile in $failedResults)
    {
        $relativePath = $failedFile.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($relativePath, $failedFile.FailureReason)) -ForegroundColor Yellow
    }
}
Write-Host ''
if ($warningResults.Count -gt 0)
{
    Write-Host ''
    Write-Host (Get-LocalizedText 'Warnings:') -ForegroundColor Cyan
    foreach ($warningResult in $warningResults)
    {
        $relativePath = $warningResult.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($relativePath, $warningResult.Warning)) -ForegroundColor Yellow
    }
}
