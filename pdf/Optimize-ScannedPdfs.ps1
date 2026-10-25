<#
.SYNOPSIS
    Processes scanned PDFs with OCR, page correction, and optional compression.

.DESCRIPTION
    Processes one PDF file or all PDF files in a specified folder and its
    subfolders. Digitally born PDFs are skipped by default; use
    -ProcessDigitallyBornPdfs to process them. Classification is heuristic:
    visible text without evidence of scanned image pages is treated as digitally
    born, while image pages with hidden OCR text are treated as scanned.
    Scanned PDFs with existing text are reprocessed by default using OCRmyPDF's
    force mode, regenerating the OCR layer while applying deskew and rotation.
    This rasterizes page content and can change output on repeated runs.
    Digitally signed PDFs and encrypted PDFs that cannot be opened without a
    password are skipped.

    On success, the input file is replaced. By default, the original is saved
    as <Name>_orig.pdf. If that backup already exists, it is preserved and the
    input is replaced directly with a warning. -ReplaceOriginal replaces the
    input without a backup.

    TWO-STAGE PROCESSING:
      1. OCRmyPDF adds an OCR text layer and deskews scans. Output is a standard
         PDF (version 1.5), not a PDF/A archive.
      2. Optional Ghostscript downsamples images and embeds them as JPEG. This
         stage runs only when -GhostscriptDpi is explicitly specified (for
         example, -GhostscriptDpi 150). The intermediate result is replaced
         only if Ghostscript makes it smaller.

    PAGE CORRECTION:
      - Skewed scans are automatically deskewed (`--deskew`, enabled by default).
      - Rotated pages (90°, 180°, 270°) are automatically detected and corrected
        by default with an OCRmyPDF confidence threshold of 5.

    LANGUAGES:
      The default sequence is 'deu+eng+fra+ita+spa+equ'. German (deu) and English
      (eng) are required. French, Italian, Spanish, and the Tesseract equation
      model (equ) are optional and removed if unavailable. No interactive
      language prompt is used.

    RESULT VALIDATION:
      A run fails only if OCRmyPDF fails or the result is byte-identical to the
      original (no change). A larger but changed result is treated as success
      and replaces the input.

    The script does not require administrator rights or install software.
    Missing dependencies are reported with installation instructions.

    OCRmyPDF progress bars and status messages are written directly to the
    console without filtering.

.PARAMETER Language
    OCR languages as '+'-separated Tesseract codes, for example 'deu+eng'.
    Default: 'deu+eng+fra+ita+spa+equ'. deu and eng are required; unavailable
    optional languages, including the equation model equ, are removed.

.PARAMETER InputPath
    Optional path to a PDF file or folder containing PDFs. If omitted, the path
    is requested interactively.

.PARAMETER JpegQuality
    JPEG quality for embedded scan images (1-100). Default: 75.

.PARAMETER GhostscriptDpi
    Target resolution for Ghostscript downsampling in DPI (50-1200). Default 0
    disables the stage. Ghostscript compression runs only when a value is
    explicitly specified, for example -GhostscriptDpi 150.

.PARAMETER NoDeskew
    Disables the default deskewing of skewed scan pages.

.PARAMETER NoRotationOfPages
    Disables automatic correction of pages rotated by 90°, 180°, or 270°.
    Rotation correction is enabled by default with a confidence threshold of 5.

.PARAMETER ProcessDigitallyBornPdfs
    Processes PDFs classified as digitally born. By default, these are skipped.
    Classification is heuristic and may not identify every mixed or unusual PDF.

.PARAMETER NoGhostscript
    Disables Ghostscript as a post-processing optimization stage. Ghostscript is
    allowed by default but runs only with -GhostscriptDpi > 0.

.PARAMETER ReplaceOriginal
    Replaces the input without a backup. By default, the original is saved as
    <Name>_orig.pdf after successful processing. An existing backup is preserved
    and the PDF is replaced directly.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.PARAMETER ForceReprocess
    Explicitly reprocesses PDFs with existing text when digitally born PDFs are
    allowed. Scanned PDFs with existing text are already reprocessed by default.
    Repeated runs can change the PDF again.

.EXAMPLE
    .\Optimize-ScannedPdfs.ps1
    Starts interactively with the default language sequence, JPEG quality 75,
    and automatic deskewing. The original is saved as an _orig file on success.

.EXAMPLE
    .\Optimize-ScannedPdfs.ps1 -InputPath 'C:\PDFs' -GhostscriptDpi 150
    Processes scanned PDFs in C:\PDFs; Ghostscript downsamples images to 150 DPI
    and compresses them as JPEG. Rotated-page correction is enabled by default.

.EXAMPLE
    .\Optimize-ScannedPdfs.ps1 -InputPath 'C:\PDFs' -ReplaceOriginal
    Processes all PDFs in C:\PDFs and replaces the originals without backups.

.EXAMPLE
    .\Optimize-ScannedPdfs.ps1 -InputPath 'C:\PDFs'
    Reprocesses scanned PDFs with existing OCR, applying deskew and rotation
    correction while regenerating their OCR text.

.EXAMPLE
    .\Optimize-ScannedPdfs.ps1 -InputPath 'C:\PDFs' -ProcessDigitallyBornPdfs
    Processes PDFs classified as digitally born instead of skipping them.

.NOTES
    Dependencies:
      - Python
      - OCRmyPDF (Python module)
      - pikepdf (used for signature checking and installed with OCRmyPDF)
      - Tesseract
      - Ghostscript (required only with -GhostscriptDpi > 0)

    Use .\Initialize-PdfProcessor.ps1 to check and install the required software.

    Tesseract language data (.traineddata) is not installed automatically. If
    required data is missing, the script points to
    https://github.com/tesseract-ocr/tessdata_best and reports the local tessdata
    folder where the files must be placed.

    TECHNICAL NOTES:
      - Output is a standard PDF version 1.5 (`--output-type pdf` for OCRmyPDF,
        `-dCompatibilityLevel=1.5` for Ghostscript), not a PDF/A archive.
      - `--optimize 1` is used instead of `--optimize 3` to avoid a jbig2 warning;
        stronger compression is optionally handled by Ghostscript.
      - OCRmyPDF ignores `--image-dpi` for PDF input, so it is not passed. Image
        resolution is controlled only by the Ghostscript stage.
      - The file is saved as UTF-8 with BOM for correct Windows PowerShell 5.1
        character decoding.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

[CmdletBinding()]
param(
    # Optional OCR language sequence, for example 'deu+eng'. Empty uses the default.
    [string] $Language,

    # Optional path to a PDF file or a folder containing PDFs.
    [string] $InputPath,

    # JPEG quality for embedded scan images (1-100). Default: 75.
    [ValidateRange(1, 100)]
    [int] $JpegQuality = 75,

    # Target resolution for Ghostscript downsampling in DPI. Default 0 disables it.
    [ValidateRange(0, 1200)]
    [int] $GhostscriptDpi = 0,

    # Disable deskewing of skewed scan pages (enabled by default).
    [switch] $NoDeskew,

    # Disable automatic correction of pages rotated by 90°, 180°, or 270°.
    [switch] $NoRotationOfPages,

    # Process PDFs classified as digitally born (skipped by default).
    [switch] $ProcessDigitallyBornPdfs,

    # Disable the optional Ghostscript post-processing stage (disabled by default).
    [switch] $NoGhostscript,

    # Replace input without a backup (an _orig backup is created by default).
    [switch] $ReplaceOriginal,

    # Reprocess existing OCR text to allow page correction on those pages.
    # Reprocess files even when the same settings have already been applied.
    [switch] $ForceReprocess,

    # Force English console output regardless of the Windows display language.
    [switch] $EnglishOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'internal\Get-PdfPythonRuntime.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-LocalizedText.ps1')
. (Join-Path $PSScriptRoot 'internal\ConvertTo-QuotedArgument.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-ExecutablePath.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-GhostscriptExecutablePath.ps1')
. (Join-Path $PSScriptRoot 'internal\Test-PythonModule.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-MissingDependency.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-Tesseract.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-TesseractLanguages.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-LanguageDownloadHint.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-PdfInputFile.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-FileSha256.ps1')
. (Join-Path $PSScriptRoot 'internal\Optimize-WithGhostscript.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-PdfProcessing.ps1')

$script:OutputLanguage = if (
    $EnglishOutput -or [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'de'
) { 'en' } else { 'de' }
$script:GermanMessages = if ($script:OutputLanguage -eq 'de') {
    Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1')
}
else { @{} }

# Default OCR language sequence: German, English, French, Italian, Spanish, and
# Tesseract's optional equation recognition model.
$script:DefaultLanguage = 'deu+eng+fra+ita+spa+equ'

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
    '     |  | PDF OCR & OPTIMIZATION              |  | |'
    '     |  | OCR / DESKEW / COMPRESS             |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)

Write-Host ''
foreach ($headerLine in $headerLines) {
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText '  Adds OCR text layers, deskews pages and optimizes PDFs.') -ForegroundColor Cyan
if (-not $ReplaceOriginal) {
    Write-Host (Get-LocalizedText '  Originals are saved as _orig files.') -ForegroundColor Cyan
}
else {
    Write-Host (Get-LocalizedText '  Originals are replaced without a backup.') -ForegroundColor Cyan
}
Write-Host ''

# Check required programs and modules before processing so all installation
# instructions can be shown together.
$pythonRuntime = Get-PdfPythonRuntime
$ghostscriptPath = if (-not $NoGhostscript.IsPresent) { Get-GhostscriptExecutablePath }
$dependencyCheck = Get-MissingDependency -PythonRuntime $pythonRuntime `
    -TesseractPath (Get-ExecutablePath -Name 'tesseract') -GhostscriptPath $ghostscriptPath `
    -NoGhostscript $NoGhostscript.IsPresent -UiLanguage $script:OutputLanguage -Messages $script:GermanMessages
if ($dependencyCheck.Missing.Count -gt 0) {
    Write-Host "`n$(Get-LocalizedText 'Missing dependencies:')" -ForegroundColor Yellow
    $dependencyCheck.Missing | ForEach-Object { Write-Host "  - $_" }
    Write-Host "`n$(Get-LocalizedText 'Run Initialize-PdfProcessor.ps1 to install the missing dependencies.')"
    exit 1
}
if ($dependencyCheck.OptionalMissing.Count -gt 0) {
    Write-Host "`n$(Get-LocalizedText 'Optional tools not found (optimization will be limited):')" -ForegroundColor DarkYellow
    $dependencyCheck.OptionalMissing | ForEach-Object { Write-Host "  - $_" }
    Write-Host (Get-LocalizedText '  Installation (elevated shell): choco install ghostscript -y')
    Write-Host (Get-LocalizedText '  Open a new PowerShell session and restart the script.')
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
        Write-Host (Get-LocalizedText '  -Language <languages>  OCR languages, e.g. deu+eng (default: deu+eng+fra+ita+spa+equ).')
        Write-Host (Get-LocalizedText '  -JpegQuality <1-100>   JPEG quality (default: 75).')
        Write-Host (Get-LocalizedText '  -GhostscriptDpi <DPI>  Optional Ghostscript resolution (default: disabled).')
        Write-Host (Get-LocalizedText '  -NoDeskew              Disable deskewing (enabled by default).')
        Write-Host (Get-LocalizedText '  -NoRotationOfPages     Disable rotation correction (enabled by default).')
        Write-Host (Get-LocalizedText '  -ProcessDigitallyBornPdfs Process PDFs classified as digitally born (default: skip).')
        Write-Host (Get-LocalizedText '  -NoGhostscript         Disable Ghostscript compression (allowed by default).')
        Write-Host (Get-LocalizedText '  -ReplaceOriginal       Replace original without an _orig backup.')
        Write-Host (Get-LocalizedText '  -ForceReprocess        Explicitly reprocess eligible PDFs.')
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
# The default sequence is deu+eng+fra+ita+spa+equ. -Language can override it.
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
Write-Host (Get-LocalizedText '=== PDF optimization: processing started ===') -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Number of files: {0}' -Arguments @($pdfFiles.Count))
Write-Host (Get-LocalizedText -Text 'Languages: {0}' -Arguments @($languageSelection))
Write-Host (Get-LocalizedText -Text 'JPEG quality: {0}' -Arguments @($JpegQuality))
if ($GhostscriptDpi -gt 0) {
    Write-Host (Get-LocalizedText -Text 'Ghostscript DPI: {0}' -Arguments @($GhostscriptDpi))
}
else {
    Write-Host (Get-LocalizedText 'Ghostscript DPI: disabled (compression requires -GhostscriptDpi)')
}
Write-Host (Get-LocalizedText -Text 'Deskew: {0}' -Arguments @(-not $NoDeskew))
Write-Host (Get-LocalizedText -Text 'Rotation correction: {0}' -Arguments @(-not $NoRotationOfPages))
Write-Host (Get-LocalizedText -Text 'Process digitally born PDFs: {0}' -Arguments @($ProcessDigitallyBornPdfs.IsPresent))
Write-Host (Get-LocalizedText 'Existing OCR on scanned PDFs is rebuilt by default to apply page corrections.')
if ($ForceReprocess) {
    Write-Host (Get-LocalizedText 'Force reprocessing: enabled')
}
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
        -Language $languageSelection -Quality $JpegQuality -GhostscriptDpi $GhostscriptDpi `
        -NoDeskew $NoDeskew.IsPresent -NoRotationOfPages $NoRotationOfPages.IsPresent `
        -ProcessDigitallyBornPdfs $ProcessDigitallyBornPdfs.IsPresent `
        -NoGhostscript $NoGhostscript.IsPresent -ReplaceOriginal $ReplaceOriginal.IsPresent `
        -ForceReprocess $ForceReprocess.IsPresent `
        -GhostscriptPath $dependencyCheck.GhostscriptPath `
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
Write-Host (Get-LocalizedText 'Skipped files:') -ForegroundColor Cyan
if ($skippedCount -eq 0) {
    Write-Host (Get-LocalizedText '  None.')
}
else {
    foreach ($skippedFile in $skippedResults) {
        $relativePath = $skippedFile.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($relativePath, $skippedFile.FailureReason)) -ForegroundColor Yellow
    }
}
if ($warningResults.Count -gt 0) {
    Write-Host ''
    Write-Host (Get-LocalizedText 'Warnings:') -ForegroundColor Cyan
    foreach ($warningResult in $warningResults) {
        $relativePath = $warningResult.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($relativePath, $warningResult.Warning)) -ForegroundColor Yellow
    }
}
