<#
.SYNOPSIS
    Adds OCR and corrects scanned PDF pages.

.DESCRIPTION
    Processes one PDF file or all PDF files in a specified folder and its
    subfolders. Digitally born PDFs are skipped. Classification is heuristic:
    visible text without evidence of scanned image pages is treated as digitally
    born, while image pages with hidden OCR text are treated as scanned.
    Existing OCR text is preserved. Page rotation is detected separately and
    applied as PDF page rotation metadata without regenerating the text layer.
    In documents with partial OCR, OCRmyPDF adds text only to pages without
    existing text. Deskewing is applied only to pages that still need OCR.
    Digitally signed PDFs and encrypted PDFs that cannot be opened without a
    password cannot be processed and are reported as issues.

    On success, the input file is replaced. By default, the original is saved
    as <Name>_orig.pdf. If that backup already exists, it is preserved and the
    input is replaced directly with a warning. -ReplaceOriginal replaces the
    input without a backup.

    OCRmyPDF adds an OCR text layer and applies page correction. Image quality
    optimization is handled separately by Optimize-PdfSize.ps1.

    PAGE CORRECTION:
      - Skewed scans are automatically deskewed (`--deskew`, enabled by default).
      - Rotated pages (90°, 180°, 270°) are automatically detected and corrected
        by default. Pages with existing text use Tesseract orientation detection
        and require Ghostscript to render page previews; the existing PDF content
        and OCR text are preserved while page rotation is updated.

    LANGUAGES:
      The default sequence is 'deu+eng+fra+ita+spa'. German (deu) and English
      (eng) are required. French, Italian, and Spanish are optional and removed
      if unavailable. No interactive language prompt is used.

    RESULT VALIDATION:
      Processing failures are reported and leave the input unchanged. A result
      identical to the original is discarded. A larger but changed result is
      treated as success and replaces the input.
      The summary does not list routine skips or unchanged files; encrypted and
      digitally signed PDFs are reported among the files with issues.

    The script does not require administrator rights or install software.
    Missing dependencies are reported with installation instructions.

    OCRmyPDF progress bars and status messages are written directly to the
    console without filtering.

.PARAMETER Language
    OCR languages as '+'-separated Tesseract codes, for example 'deu+eng'.
    Default: 'deu+eng+fra+ita+spa'. deu and eng are required; unavailable
    optional languages are removed.

.PARAMETER InputPath
    Optional path to a PDF file or folder containing PDFs. If omitted, the path
    is requested interactively.

.PARAMETER NoDeskew
    Disables deskewing of pages that require OCR. Pages that already have text
    are not deskewed or rasterized.

.PARAMETER NoRotationOfPages
    Disables automatic correction of pages rotated by 90°, 180°, or 270°.
    Rotation correction is enabled by default with a confidence threshold of 5.

.PARAMETER ReplaceOriginal
    Replaces the input without a backup. By default, the original is saved as
    <Name>_orig.pdf after successful processing. An existing backup is preserved
    and the PDF is replaced directly.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.EXAMPLE
    .\ConvertTo-SearchablePdf.ps1
    Starts interactively with the default language sequence and automatic
    deskewing. The original is saved as an _orig file on success.

.EXAMPLE
    .\ConvertTo-SearchablePdf.ps1 -InputPath 'C:\PDFs'
    Processes scanned PDFs in C:\PDFs. Rotated-page correction is enabled by default.

.EXAMPLE
    .\ConvertTo-SearchablePdf.ps1 -InputPath 'C:\PDFs' -ReplaceOriginal
    Processes all PDFs in C:\PDFs and replaces the originals without backups.

.EXAMPLE
    .\ConvertTo-SearchablePdf.ps1 -InputPath 'C:\PDFs'
    Preserves existing OCR text and corrects page rotation; OCR is added only
    to scanned pages that do not already have text.

.NOTES
    Dependencies:
      - Python
      - OCRmyPDF (Python module)
      - pikepdf (used for signature checking and installed with OCRmyPDF)
      - Tesseract
      - Ghostscript (optional for ordinary OCR; used for rotation-only
        correction when a scanned PDF already has text)

    This script checks its dependencies and prints installation guidance when
    a required executable or Python module is missing.

    Tesseract language data (.traineddata) is not installed automatically. If
    required data is missing, the script points to
    https://github.com/tesseract-ocr/tessdata_best and reports the local tessdata
    folder where the files must be placed.

    TECHNICAL NOTES:
      - Output is a standard PDF version 1.5 (`--output-type pdf`), not a PDF/A
        archive.
      - `--optimize 0` disables OCRmyPDF image optimization; use
        Optimize-PdfSize.ps1 for image downsampling and JPEG compression.
      - OCRmyPDF ignores `--image-dpi` for PDF input, so it is not passed.
      - The file is saved as UTF-8 with BOM for correct Windows PowerShell 5.1
        character decoding.
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
    # Optional OCR language sequence, for example 'deu+eng'. Empty uses the default.
    [string] $Language,

    # Optional path to a PDF file or a folder containing PDFs.
    [string] $InputPath,

# Disable deskewing on pages that need OCR (enabled by default).
    [switch] $NoDeskew,

    # Disable automatic correction of pages rotated by 90°, 180°, or 270°.
    [switch] $NoRotationOfPages,

    # Replace input without a backup (an _orig backup is created by default).
    [switch] $ReplaceOriginal,

    # Force English console output regardless of the Windows display language.
    [switch] $EnglishOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'internal\Get-PdfPythonRuntime.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-LocalizedText.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-MissingDependencyReport.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\ConvertTo-QuotedArgument.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-ExecutablePath.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-GhostscriptExecutablePath.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-SetupProcess.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-PythonCommand.ps1')
. (Join-Path $PSScriptRoot 'internal\Test-PythonModule.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-MissingDependency.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-Tesseract.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-TesseractLanguages.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-LanguageDownloadHint.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-PdfInputFile.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-FileSha256.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-PdfRotationOnly.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-PdfProcessing.ps1')

$script:OutputLanguage = if (
    $EnglishOutput -or [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'de'
) { 'en' } else { 'de' }
$script:GermanMessages = if ($script:OutputLanguage -eq 'de') {
    Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1')
}
else { @{} }

# Default OCR language sequence: German, English, French, Italian, and Spanish.
$script:DefaultLanguage = 'deu+eng+fra+ita+spa'

# Required languages: processing stops with a notice if deu or eng is missing.
$script:RequiredLanguages = @('deu', 'eng')

# Source for Tesseract language data (.traineddata), which users must download
# and place in the local tessdata folder.
$script:TessdataUrl = 'https://github.com/tesseract-ocr/tessdata_best'



# --- Main program ---------------------------------------------------------

# Document-style banner describing the script's purpose.
$headerLines = @(
    '       .-------------------------------------------.'
    '      /                                           /|'
    '     /___________________________________________/ |'
    '     |  .-------------------------------------.  | |'
    '     |  | PDF OCR & PAGE CORRECTION           |  | |'
    '     |  | OCR / DESKEW / ROTATE               |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)

Write-Host ''
foreach ($headerLine in $headerLines) {
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText '  Adds OCR text layers, deskews pages and corrects page orientation.') -ForegroundColor Cyan
if (-not $ReplaceOriginal) {
    Write-Host (Get-LocalizedText '  Originals are saved as _orig files.') -ForegroundColor Cyan
}
else {
    Write-Host (Get-LocalizedText '  Originals are replaced without a backup.') -ForegroundColor Cyan
}
Write-Host ''

# Check required programs and modules before processing.
$pythonRuntime = Get-PdfPythonRuntime
$missingDependencyTemplate = Get-LocalizedText -Text 'Missing dependency: {0}'
$dependencyCheck = Get-MissingDependency -PythonRuntime $pythonRuntime `
    -TesseractPath (Get-ExecutablePath -Name 'tesseract') `
    -GhostscriptPath (Get-GhostscriptExecutablePath) -NoGhostscript $false `
    -UiLanguage $script:OutputLanguage -Messages $script:GermanMessages
if ($dependencyCheck.Missing.Count -gt 0) {
    foreach ($dependency in $dependencyCheck.Missing)
    {
        $guidance = switch ($dependency)
        {
            (Get-LocalizedText 'Python interpreter') {
                Get-LocalizedText 'Install Python from https://www.python.org/downloads/.'
                break
            }
            'Tesseract' {
                Get-LocalizedText 'Install Tesseract with Chocolatey: choco install tesseract -y, or download from https://github.com/UB-Mannheim/tesseract/wiki.'
                break
            }
            (Get-LocalizedText 'OCRmyPDF (Python module)') {
                Get-LocalizedText -Text 'Install the Python module with the selected interpreter: "{0}" -m pip install {1}.' `
                    -Arguments @($dependencyCheck.PythonPath, 'ocrmypdf')
                break
            }
            (Get-LocalizedText 'pikepdf (Python module)') {
                Get-LocalizedText -Text 'Install the Python module with the selected interpreter: "{0}" -m pip install {1}.' `
                    -Arguments @($dependencyCheck.PythonPath, 'pikepdf')
                break
            }
        }
        $report = Get-MissingDependencyReport -Dependency $dependency -Guidance $guidance `
            -MessageTemplate $missingDependencyTemplate
        Write-Host $report.Message -ForegroundColor Yellow
        Write-Host "  $( $report.Guidance )"
    }
    exit 1
}
if ($dependencyCheck.OptionalMissing.Count -gt 0) {
    foreach ($dependency in $dependencyCheck.OptionalMissing)
    {
        $report = Get-MissingDependencyReport -Dependency $dependency `
            -Guidance (Get-LocalizedText 'Install Ghostscript with Chocolatey: choco install ghostscript -y, or download from https://ghostscript.com/releases/gsdnld.html.') `
            -MessageTemplate $missingDependencyTemplate
        Write-Host $report.Message -ForegroundColor DarkYellow
        Write-Host "  $( $report.Guidance )"
    }
    Write-Host (Get-LocalizedText 'Open a new PowerShell session and restart the script.')
    Write-Host ''
}

# --- Get Tesseract languages and tessdata folder --------------------------
$tesseractPath = Get-ExecutablePath -Name 'tesseract'
try {
    $tesseractInfo = Get-TesseractLanguages -TesseractPath $tesseractPath -UiLanguage $script:OutputLanguage -Messages $script:GermanMessages
}
catch {
    Write-Error (Get-LocalizedText -Text 'Could not get Tesseract languages. Check "tesseract --list-langs": {0}' -Arguments @($_.Exception.Message))
    exit 1
}
$installedLanguages = @($tesseractInfo.Languages)

# --- Discover input files --------------------------------------------------
# Interactive help is shown only when no path was passed on the command line.
try {
    $selectedPath = $InputPath
    if ([string]::IsNullOrWhiteSpace($selectedPath)) {
        Write-Host ''
        Write-Host (Get-LocalizedText 'Available parameters:') -ForegroundColor Cyan
        Write-Host (Get-LocalizedText '  -InputPath <path>       PDF file or folder; prompts if omitted.')
        Write-Host (Get-LocalizedText '  -Language <languages>  OCR languages, e.g. deu+eng (default: deu+eng+fra+ita+spa).')
        Write-Host (Get-LocalizedText '  -NoDeskew              Disable deskewing on pages needing OCR (enabled by default).')
        Write-Host (Get-LocalizedText '  -NoRotationOfPages     Disable rotation correction (enabled by default).')
        Write-Host (Get-LocalizedText '  -ReplaceOriginal       Replace original without an _orig backup.')
        Write-Host (Get-LocalizedText '  -EnglishOutput         Force English console output.')
        Write-Host (Get-LocalizedText 'Press Ctrl+C to cancel input.') -ForegroundColor Yellow
        $selectedPath = Read-Host -Prompt (Get-LocalizedText 'Path to a PDF file or a folder containing PDFs')
    }
    $inputSelection = Get-PdfInputFile -Path $selectedPath -UiLanguage $script:OutputLanguage -Messages $script:GermanMessages
}
catch { Write-Error $_.Exception.Message; exit 1 }
$pdfFiles = @($inputSelection.Files)
if ($pdfFiles.Count -eq 0) { Write-Host (Get-LocalizedText 'No PDFs found.'); exit 0 }
$inputBasePath = $inputSelection.BasePath
$summaryPathSegments = @($inputBasePath.TrimEnd('\') -split '[\\/]' | Where-Object { $_ })
$summaryPathTail = @($summaryPathSegments | Select-Object -Last 3)
$summaryPath = '.\' + ($summaryPathTail -join '\') + '\'
$basePathPrefix = $inputBasePath
if (-not $basePathPrefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar)) {
    $basePathPrefix += [System.IO.Path]::DirectorySeparatorChar
}

# --- Configure language sequence ------------------------------------------
# The default sequence is deu+eng+fra+ita+spa. -Language can override it.
# There is no interactive language prompt. deu and eng are required; missing
# optional languages are removed from the sequence.
if (-not [string]::IsNullOrWhiteSpace($Language)) {
    $languageSelection = $Language.Trim()
}
else {
    $languageSelection = $script:DefaultLanguage
}

# Preserve the requested order when passing languages to OCRmyPDF.
$requestedLanguages = @($languageSelection -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# Stop and show the download instructions if a required language is missing.
$missingRequired = @($requestedLanguages | Where-Object { $script:RequiredLanguages -contains $_ -and $installedLanguages -notcontains $_ })
if ($missingRequired.Count -gt 0) {
    Write-Host ''
    Get-LanguageDownloadHint -MissingLanguages $missingRequired -TessdataPath $tesseractInfo.TessdataPath `
        -TessdataUrl $script:TessdataUrl -UiLanguage $script:OutputLanguage -Messages $script:GermanMessages |
        ForEach-Object { Write-Host $_ }
    exit 1
}

# Silently remove unavailable optional languages.
$availableLanguages = @($requestedLanguages | Where-Object { $installedLanguages -contains $_ })
$droppedLanguages = @($requestedLanguages | Where-Object { $installedLanguages -notcontains $_ })
if ($droppedLanguages.Count -gt 0) {
    Write-Host (Get-LocalizedText -Text 'Notice: these languages are not installed and will be removed: {0}' -Arguments @(($droppedLanguages -join ', '))) -ForegroundColor DarkYellow
}
if ($availableLanguages.Count -eq 0) {
    Write-Error (Get-LocalizedText 'None of the requested languages is installed.')
    exit 1
}
$languageSelection = $availableLanguages -join '+'

# Run summary header.
Write-Host ''
Write-Host (Get-LocalizedText '=== PDF OCR: processing started ===') -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Number of files: {0}' -Arguments @($pdfFiles.Count))
Write-Host (Get-LocalizedText -Text 'Languages: {0}' -Arguments @($languageSelection))
Write-Host (Get-LocalizedText -Text 'Deskew on pages needing OCR: {0}' -Arguments @(-not $NoDeskew))
Write-Host (Get-LocalizedText -Text 'Rotation correction: {0}' -Arguments @(-not $NoRotationOfPages))
Write-Host (Get-LocalizedText 'Existing OCR is preserved; page rotation is corrected without regenerating OCR.')
Write-Host (Get-LocalizedText 'Output format: standard PDF (version 1.5)')

# --- Process PDFs ---------------------------------------------------------
# Routes the processing messages to the console: warnings through Write-Warning,
# everything else through Write-Host with the optional color.
$reporter = {
    param($Kind, $Color, $Text)
    if ($Kind -eq 'Warning') { Write-Warning $Text; return }
    if ($Color) { Write-Host $Text -ForegroundColor $Color }
    else { Write-Host $Text }
}
$results = @()
for ($i = 0; $i -lt $pdfFiles.Count; $i++) {
    $pdf = $pdfFiles[$i]
    Write-Host ''
    Write-Host (Get-LocalizedText -Text '--- File {0}/{1}: {2} ---' -Arguments @(($i + 1), $pdfFiles.Count, $pdf.Name)) -ForegroundColor Cyan
    $r = Invoke-PdfProcessing -Pdf $pdf -PythonPath $dependencyCheck.PythonPath `
        -Language $languageSelection `
        -NoDeskew $NoDeskew.IsPresent -NoRotationOfPages $NoRotationOfPages.IsPresent `
        -ReplaceOriginal $ReplaceOriginal.IsPresent -GhostscriptPath $dependencyCheck.GhostscriptPath `
        -TesseractPath $tesseractPath `
        -UiLanguage $script:OutputLanguage -Messages $script:GermanMessages -Reporter $reporter
    if ($null -ne $r) { $results += $r }
}

# --- Summary ---------------------------------------------------------------
$successResults = @($results | Where-Object { $_.Success })
$skippedResults = @($results | Where-Object { $_.Skipped })
$failedResults = @($results | Where-Object { -not $_.Success -and -not $_.Skipped })
$warningResults = @($results | Where-Object { $_.Warning })
$successCount = $successResults.Count
$skippedCount = $skippedResults.Count
$failureCount = $failedResults.Count
$sumOriginal = [long](($results | ForEach-Object { [long]$_.OriginalBytes }) | Measure-Object -Sum).Sum
$sumResult = [long](($successResults | ForEach-Object { [long]$_.ResultBytes }) | Measure-Object -Sum).Sum
$savedMb = ($sumOriginal - $sumResult) / 1MB
$savedPct = if ($sumOriginal -gt 0) { (1 - ($sumResult / $sumOriginal)) * 100 } else { 0 }

Write-Host ''
Write-Host (Get-LocalizedText '=== Summary ===') -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath))
Write-Host (Get-LocalizedText -Text 'Succeeded: {0}, skipped: {1}, failed: {2}' -Arguments @($successCount, $skippedCount, $failureCount))
if ($successCount -gt 0) {
    Write-Host (Get-LocalizedText -Text 'Original total: {0:N2} MB' -Arguments @(($sumOriginal / 1MB)))
    Write-Host (Get-LocalizedText -Text 'Result total: {0:N2} MB' -Arguments @(($sumResult / 1MB)))
    Write-Host (Get-LocalizedText -Text 'Total saved: {0:N2} MB ({1:N1}%)' -Arguments @($savedMb, $savedPct))
}
if (-not $ReplaceOriginal) {
    Write-Host (Get-LocalizedText 'Originals are saved as _orig files; existing backups are preserved.')
}
else {
    Write-Host (Get-LocalizedText 'Originals were replaced.')
}
Write-Host ''
Write-Host (Get-LocalizedText 'Failed files:') -ForegroundColor Cyan
if ($failedResults.Count -eq 0) {
    Write-Host (Get-LocalizedText '  None.')
}
else {
    foreach ($failedFile in $failedResults) {
        $relativePath = $failedFile.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($relativePath, $failedFile.FailureReason)) -ForegroundColor Yellow
    }
}
Write-Host ''
if ($warningResults.Count -gt 0) {
    Write-Host ''
    Write-Host (Get-LocalizedText 'Warnings:') -ForegroundColor Cyan
    foreach ($warningResult in $warningResults) {
        $relativePath = $warningResult.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($relativePath, $warningResult.Warning)) -ForegroundColor Yellow
    }
}
