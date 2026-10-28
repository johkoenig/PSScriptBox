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
    This script checks its dependencies and prints installation guidance when
    a required executable or Python module is missing.
    No files are modified, and administrator rights are not required.
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
    [string] $InputPath,

    [switch] $EnglishOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'internal\Get-PdfPythonRuntime.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-LocalizedText.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-MissingDependencyReport.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\ConvertTo-QuotedArgument.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-PythonCommand.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-PdfTextLayerStatus.ps1')

$OutputLanguage = if (
    $EnglishOutput -or [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'de'
) { 'en' } else { 'de' }
$MessagesPath = Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1'

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
Write-Host (Get-LocalizedText 'Finds PDFs with missing text layers.' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
Write-Host ''

# --- Input and dependencies ----------------------------------------------

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    Write-Host (Get-LocalizedText 'Enter the path to a PDF file or a folder containing PDFs.' -Language $OutputLanguage -MessagesPath $MessagesPath)
    $InputPath = Read-Host -Prompt (Get-LocalizedText 'InputPath' -Language $OutputLanguage -MessagesPath $MessagesPath)
}
$InputPath = [Environment]::ExpandEnvironmentVariables($InputPath.Trim().Trim('"'))
if ([string]::IsNullOrWhiteSpace($InputPath)) {
    throw (Get-LocalizedText 'No path was specified.' -Language $OutputLanguage -MessagesPath $MessagesPath)
}

$missingDependencyTemplate = Get-LocalizedText -Text 'Missing dependency: {0}' -Language $OutputLanguage -MessagesPath $MessagesPath
$pythonRuntime = Get-PdfPythonRuntime
if (-not $pythonRuntime) {
    $report = Get-MissingDependencyReport -Dependency 'Python' `
        -Guidance (Get-LocalizedText 'Install Python from https://www.python.org/downloads/.' -Language $OutputLanguage -MessagesPath $MessagesPath) `
        -MessageTemplate $missingDependencyTemplate
    Write-Host $report.Message -ForegroundColor Yellow
    Write-Host "  $( $report.Guidance )"
    exit 1
}
$pythonPath = $pythonRuntime.Path

$moduleCheck = Invoke-PythonCommand -PythonPath $pythonPath -Arguments @('-c', 'import pikepdf')
if ($moduleCheck.ExitCode -ne 0) {
    $report = Get-MissingDependencyReport -Dependency 'pikepdf (Python module)' `
        -Guidance (Get-LocalizedText -Text 'Install pikepdf with the selected interpreter: "{0}" -m pip install pikepdf.' `
            -Arguments @($pythonPath) -Language $OutputLanguage -MessagesPath $MessagesPath) `
        -MessageTemplate $missingDependencyTemplate

    Write-Host $report.Message -ForegroundColor Yellow
    Write-Host "  $( $report.Guidance )"
    exit 1
}

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw (Get-LocalizedText -Text 'The specified path was not found: {0}' -Arguments @($InputPath) -Language $OutputLanguage -MessagesPath $MessagesPath)
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
    throw (Get-LocalizedText -Text 'The path must point to a PDF file or a folder: {0}' -Arguments @($InputPath) -Language $OutputLanguage -MessagesPath $MessagesPath)
}

if ($pdfFiles.Count -eq 0) {
    Write-Host (Get-LocalizedText 'No PDFs found.' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Green
    exit 0
}

$basePathPrefix = $baseDirectory
if (-not $basePathPrefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar)) {
    $basePathPrefix += [System.IO.Path]::DirectorySeparatorChar
}

# --- Check PDFs -----------------------------------------------------------

Write-Host (Get-LocalizedText -Text '  Folder: {0}' -Arguments @($baseDirectory) -Language $OutputLanguage -MessagesPath $MessagesPath)
Write-Host (Get-LocalizedText -Text '  PDFs to check: {0}' -Arguments @($pdfFiles.Count) -Language $OutputLanguage -MessagesPath $MessagesPath)

$results = @(
    for ($index = 0; $index -lt $pdfFiles.Count; $index++) {
        $pdf = $pdfFiles[$index]
        $relativePath = $pdf.FullName.Substring($basePathPrefix.Length)
        Write-Host ''
        Write-Host (Get-LocalizedText -Text '--- PDF {0}/{1}: {2} ---' -Arguments @(($index + 1), $pdfFiles.Count, $relativePath) -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
        try {
            $result = Get-PdfTextLayerStatus -Pdf $pdf -PythonPath $pythonPath -UiLanguage $OutputLanguage -MessagesPath $MessagesPath
            switch ($result.Status) {
                'NoTextLayer' {
                    Write-Host (Get-LocalizedText 'No text layer found.' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Yellow
                }
                'PartialTextLayer' {
                    Write-Host (Get-LocalizedText -Text 'Text found on only {0} of {1} pages.' -Arguments @($result.TextPageCount, $result.PageCount) -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor DarkYellow
                }
                default {
                    Write-Host (Get-LocalizedText -Text 'Text found on all {0} pages.' -Arguments @($result.PageCount) -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Green
                }
            }
            $result
        }
        catch {
            Write-Warning (Get-LocalizedText -Text "Could not check PDF: '{0}'`n{1}" -Arguments @($relativePath, $_.Exception.Message) -Language $OutputLanguage -MessagesPath $MessagesPath)
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
Write-Host (Get-LocalizedText '=== Summary ===' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Checked: {0}, no text layer: {1}, partial: {2}, with text layer: {3}, errors: {4}' -Arguments @(
    $results.Count, $withoutText.Count, $partialText.Count, $withText.Count, $errors.Count
) -Language $OutputLanguage -MessagesPath $MessagesPath)

Write-Host ''
Write-Host (Get-LocalizedText 'PDFs without a text layer:' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
if ($withoutText.Count -eq 0) {
    Write-Host (Get-LocalizedText '  None.' -Language $OutputLanguage -MessagesPath $MessagesPath)
}
else {
    foreach ($result in $withoutText) {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1} pages)' -Arguments @($relativePath, $result.PageCount) -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Yellow
    }
}

if ($partialText.Count -gt 0) {
    Write-Host ''
    Write-Host (Get-LocalizedText 'PDFs with a partially missing text layer:' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
    foreach ($result in $partialText) {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        $pagesWithoutText = $result.PageCount - $result.TextPageCount
        Write-Host (Get-LocalizedText -Text '  - {0} ({1} of {2} pages without text)' -Arguments @($relativePath, $pagesWithoutText, $result.PageCount) -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor DarkYellow
    }
}

if ($errors.Count -gt 0) {
    Write-Host ''
    Write-Host (Get-LocalizedText 'PDFs that could not be checked:' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
    foreach ($result in $errors) {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($relativePath, $result.Error) -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Red
    }
}
