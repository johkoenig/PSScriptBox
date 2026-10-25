<#
.SYNOPSIS
    Finds PDF files without a searchable text layer.

.DESCRIPTION
    Checks a PDF file or all PDFs in a folder and its subfolders. PDF text
    operators in page content and embedded forms are detected. Files with no
    text operators and PDFs with text on only some pages are listed separately.
    The script does not assess text quality or searchability and does not modify
    file contents.

.PARAMETER InputPath
    PDF file or folder to search recursively. If omitted, the path is requested
    interactively.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.EXAMPLE
    .\Find-PdfsWithoutTextLayer.ps1 -InputPath 'C:\PDFs'
    Checks all PDFs in C:\PDFs and its subfolders.

.EXAMPLE
    .\Find-PdfsWithoutTextLayer.ps1 -InputPath 'C:\PDFs\Scan.pdf'
    Checks only the specified PDF file.

.NOTES
    Dependencies: PowerShell 5.1 or later, Python, and the pikepdf Python module.
    Use .\Initialize-PdfProcessor.ps1 to install missing dependencies into the
    selected Python interpreter.
    No files are modified, and administrator rights are not required.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

[CmdletBinding()]
param(
    [string] $InputPath,

    [switch] $EnglishOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'internal\Get-PdfPythonRuntime.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-LocalizedText.ps1')
. (Join-Path $PSScriptRoot 'internal\ConvertTo-QuotedArgument.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-PythonCommand.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-PdfTextLayerStatus.ps1')

$script:OutputLanguage = if (
    $EnglishOutput -or [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'de'
) { 'en' } else { 'de' }
$script:GermanMessages = if ($script:OutputLanguage -eq 'de') {
    Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1')
}
else { @{} }

$headerLines = @(
    '       .-------------------------------------------.'
    '      /                                           /|'
    '     /___________________________________________/ |'
    '     |  .-------------------------------------.  | |'
    '     |  | PDF TEXT LAYER INSPECTOR            |  | |'
    '     |  | FIND / CHECK / CLASSIFY             |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)

Write-Host ''
foreach ($headerLine in $headerLines) {
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText 'Finds PDFs with missing text layers.') -ForegroundColor Cyan
Write-Host ''

# --- Input and dependencies ----------------------------------------------

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    Write-Host (Get-LocalizedText 'Enter the path to a PDF file or a folder containing PDFs.')
    $InputPath = Read-Host -Prompt (Get-LocalizedText 'InputPath')
}
$InputPath = [Environment]::ExpandEnvironmentVariables($InputPath.Trim().Trim('"'))
if ([string]::IsNullOrWhiteSpace($InputPath)) {
    throw (Get-LocalizedText 'No path was specified.')
}

$pythonRuntime = Get-PdfPythonRuntime
if (-not $pythonRuntime) {
    Write-Host (Get-LocalizedText 'Missing dependency: Python.') -ForegroundColor Yellow
    Write-Host (Get-LocalizedText 'Run Initialize-PdfProcessor.ps1 to install the missing dependencies.')
    exit 1
}
$pythonPath = $pythonRuntime.Path

$moduleCheck = Invoke-PythonCommand -PythonPath $pythonPath -Arguments @('-c', 'import pikepdf')
if ($moduleCheck.ExitCode -ne 0) {
    Write-Host (Get-LocalizedText 'Missing dependency: Python module pikepdf.') -ForegroundColor Yellow
    Write-Host (Get-LocalizedText 'Run Initialize-PdfProcessor.ps1 to install the missing dependencies.')
    exit 1
}

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw (Get-LocalizedText -Text 'The specified path was not found: {0}' -Arguments @($InputPath))
}

$inputItem = Get-Item -LiteralPath $InputPath
if ($inputItem -is [System.IO.DirectoryInfo]) {
    $baseDirectory = $inputItem.FullName
    $pdfFiles = @(Get-ChildItem -LiteralPath $baseDirectory -File -Recurse -Filter '*.pdf' |
        Sort-Object -Property FullName)
}
elseif ($inputItem -is [System.IO.FileInfo] -and $inputItem.Extension -ieq '.pdf') {
    $baseDirectory = $inputItem.DirectoryName
    $pdfFiles = @($inputItem)
}
else {
    throw (Get-LocalizedText -Text 'The path must point to a PDF file or a folder: {0}' -Arguments @($InputPath))
}

if ($pdfFiles.Count -eq 0) {
    Write-Host (Get-LocalizedText 'No PDFs found.') -ForegroundColor Green
    exit 0
}

$basePathPrefix = $baseDirectory
if (-not $basePathPrefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar)) {
    $basePathPrefix += [System.IO.Path]::DirectorySeparatorChar
}

# --- Check PDFs -----------------------------------------------------------

Write-Host (Get-LocalizedText -Text '  Folder: {0}' -Arguments @($baseDirectory))
Write-Host (Get-LocalizedText -Text '  PDFs to check: {0}' -Arguments @($pdfFiles.Count))

$results = @(
    for ($index = 0; $index -lt $pdfFiles.Count; $index++) {
        $pdf = $pdfFiles[$index]
        $relativePath = $pdf.FullName.Substring($basePathPrefix.Length)
        Write-Host ''
        Write-Host (Get-LocalizedText -Text '--- PDF {0}/{1}: {2} ---' -Arguments @(($index + 1), $pdfFiles.Count, $relativePath)) -ForegroundColor Cyan
        try {
            $result = Get-PdfTextLayerStatus -Pdf $pdf -PythonPath $pythonPath -UiLanguage $script:OutputLanguage -Messages $script:GermanMessages
            switch ($result.Status) {
                'NoTextLayer' {
                    Write-Host (Get-LocalizedText 'No text layer found.') -ForegroundColor Yellow
                }
                'PartialTextLayer' {
                    Write-Host (Get-LocalizedText -Text 'Text found on only {0} of {1} pages.' -Arguments @($result.TextPageCount, $result.PageCount)) -ForegroundColor DarkYellow
                }
                default {
                    Write-Host (Get-LocalizedText -Text 'Text found on all {0} pages.' -Arguments @($result.PageCount)) -ForegroundColor Green
                }
            }
            $result
        }
        catch {
            Write-Warning (Get-LocalizedText -Text "Could not check PDF: '{0}'`n{1}" -Arguments @($relativePath, $_.Exception.Message))
            [pscustomobject]@{
                FilePath      = $pdf.FullName
                PageCount     = 0
                TextPageCount = 0
                Status        = 'Error'
                Error         = $_.Exception.Message
            }
        }
    }
)

# --- Summary --------------------------------------------------------------

$withoutText = @($results | Where-Object { $_.Status -eq 'NoTextLayer' })
$partialText = @($results | Where-Object { $_.Status -eq 'PartialTextLayer' })
$withText = @($results | Where-Object { $_.Status -eq 'TextLayerPresent' })
$errors = @($results | Where-Object { $_.Status -eq 'Error' })

Write-Host ''
Write-Host (Get-LocalizedText '=== Summary ===') -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Checked: {0}, no text layer: {1}, partial: {2}, with text layer: {3}, errors: {4}' -Arguments @(
    $results.Count, $withoutText.Count, $partialText.Count, $withText.Count, $errors.Count
))

Write-Host ''
Write-Host (Get-LocalizedText 'PDFs without a text layer:') -ForegroundColor Cyan
if ($withoutText.Count -eq 0) {
    Write-Host (Get-LocalizedText '  None.')
}
else {
    foreach ($result in $withoutText) {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1} pages)' -Arguments @($relativePath, $result.PageCount)) -ForegroundColor Yellow
    }
}

if ($partialText.Count -gt 0) {
    Write-Host ''
    Write-Host (Get-LocalizedText 'PDFs with a partially missing text layer:') -ForegroundColor Cyan
    foreach ($result in $partialText) {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        $pagesWithoutText = $result.PageCount - $result.TextPageCount
        Write-Host (Get-LocalizedText -Text '  - {0} ({1} of {2} pages without text)' -Arguments @($relativePath, $pagesWithoutText, $result.PageCount)) -ForegroundColor DarkYellow
    }
}

if ($errors.Count -gt 0) {
    Write-Host ''
    Write-Host (Get-LocalizedText 'PDFs that could not be checked:') -ForegroundColor Cyan
    foreach ($result in $errors) {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($relativePath, $result.Error)) -ForegroundColor Red
    }
}
