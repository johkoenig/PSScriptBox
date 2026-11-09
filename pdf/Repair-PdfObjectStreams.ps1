<#
.SYNOPSIS
    Rewrites text-bearing PDFs without object streams.

.DESCRIPTION
    Processes a PDF or all PDFs in a folder recursively. pikepdf checks for
    object streams and rewrites text-bearing PDFs only when they are present,
    improving compatibility with independent PDF text extractors. PDFs without
    object streams or text-show operators are skipped. Encrypted or digitally
    signed PDFs are not changed.

    By default, the original is saved as <Name>_orig.pdf. Existing backups are
    preserved. -ReplaceOriginal replaces the input without creating a backup.
    The operation can be previewed with -WhatIf.

.PARAMETER InputPath
    PDF file or folder to process. If omitted, prompts for a path.

.PARAMETER ReplaceOriginal
    Replaces the input without creating a new _orig backup.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows UI language.

.EXAMPLE
    .\Repair-PdfObjectStreams.ps1 -InputPath 'C:\PDFs' -WhatIf
    Previews normalization of text-bearing PDFs in C:\PDFs and its subfolders.

.EXAMPLE
    .\Repair-PdfObjectStreams.ps1 -InputPath 'C:\PDFs' -ReplaceOriginal
    Normalizes text-bearing PDFs without creating original backups.

.NOTES
    Dependencies: PowerShell 5.1 or later, Python, and the pikepdf Python
    module. This script checks dependencies and does not install software.
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

    [switch] $ReplaceOriginal,

    [switch] $EnglishOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'internal\Get-PdfPythonRuntime.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-LocalizedText.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-MissingDependencyReport.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\ConvertTo-QuotedArgument.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-FileSha256.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-PythonCommand.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-PdfInputFile.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-PdfObjectStreamNormalization.ps1')

$OutputLanguage = if (
$EnglishOutput -or [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'de'
)
{
    'en'
}
else
{
    'de'
}
$MessagesPath = Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1'

$headerLines = @(
    '       .-------------------------------------------.'
    '      /                                           /|'
    '     /___________________________________________/ |'
    '     |  .-------------------------------------.  | |'
    '     |  | PDF OBJECT STREAM REPAIR            |  | |'
    '     |  | NORMALIZE / VERIFY / REPLACE         |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)

Write-Host ''
foreach ($headerLine in $headerLines)
{
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText 'Disables object streams in text-bearing PDFs when needed.' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
if (-not $ReplaceOriginal)
{
    Write-Host "  $( Get-LocalizedText 'Originals are saved as _orig files.' -Language $OutputLanguage -MessagesPath $MessagesPath )" -ForegroundColor Cyan
}
else
{
    Write-Host "  $( Get-LocalizedText 'Originals are replaced without a backup.' -Language $OutputLanguage -MessagesPath $MessagesPath )" -ForegroundColor Cyan
}
Write-Host ''

if ( [string]::IsNullOrWhiteSpace($InputPath))
{
    Write-Host (Get-LocalizedText 'Enter the path to a PDF file or a folder containing PDFs.' -Language $OutputLanguage -MessagesPath $MessagesPath)
    $InputPath = Read-Host -Prompt (Get-LocalizedText 'InputPath' -Language $OutputLanguage -MessagesPath $MessagesPath)
}

$pythonRuntime = Get-PdfPythonRuntime
if (-not $pythonRuntime)
{
    $report = Get-MissingDependencyReport -Dependency (Get-LocalizedText 'Python (py.exe or python.exe)' -Language $OutputLanguage -MessagesPath $MessagesPath) `
        -Guidance (Get-LocalizedText 'Install Python from https://www.python.org/downloads/.' -Language $OutputLanguage -MessagesPath $MessagesPath) `
        -MessageTemplate (Get-LocalizedText -Text 'Missing dependency: {0}' -Language $OutputLanguage -MessagesPath $MessagesPath)
    Write-Host $report.Message -ForegroundColor Yellow
    Write-Host "  $( $report.Guidance )"
    exit 1
}

$pikepdfCheck = Invoke-PythonCommand -PythonPath $pythonRuntime.Path -Arguments @('-c', 'import pikepdf') `
    -UiLanguage $OutputLanguage -MessagesPath $MessagesPath
if ($pikepdfCheck.ExitCode -ne 0)
{
    $report = Get-MissingDependencyReport -Dependency (Get-LocalizedText 'pikepdf (Python module)' -Language $OutputLanguage -MessagesPath $MessagesPath) `
        -Guidance (Get-LocalizedText -Text 'Install pikepdf with the selected interpreter: "{0}" -m pip install pikepdf.' `
            -Arguments @($pythonRuntime.Path) -Language $OutputLanguage -MessagesPath $MessagesPath) `
        -MessageTemplate (Get-LocalizedText -Text 'Missing dependency: {0}' -Language $OutputLanguage -MessagesPath $MessagesPath)
    Write-Host $report.Message -ForegroundColor Yellow
    Write-Host "  $( $report.Guidance )"
    exit 1
}

try
{
    $inputSelection = Get-PdfInputFile -Path $InputPath -UiLanguage $OutputLanguage -MessagesPath $MessagesPath
}
catch
{
    Write-Error $_.Exception.Message
    exit 1
}

$pdfFiles = @($inputSelection.Files)
if ($pdfFiles.Count -eq 0)
{
    Write-Host (Get-LocalizedText 'No PDFs found.' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Green
    exit 0
}

$basePathPrefix = $inputSelection.BasePath
if (-not $basePathPrefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar))
{
    $basePathPrefix += [System.IO.Path]::DirectorySeparatorChar
}

Write-Host (Get-LocalizedText -Text '=== PDF object-stream repair: processing started ===' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($inputSelection.BasePath) -Language $OutputLanguage -MessagesPath $MessagesPath)
Write-Host (Get-LocalizedText -Text 'PDFs to process: {0}' -Arguments @($pdfFiles.Count) -Language $OutputLanguage -MessagesPath $MessagesPath)
Write-Host (Get-LocalizedText -Text 'Preserve original backup: {0}' -Arguments @(-not $ReplaceOriginal) -Language $OutputLanguage -MessagesPath $MessagesPath)

$results = @(
for ($index = 0; $index -lt $pdfFiles.Count; $index++) {
    $pdf = $pdfFiles[$index]
    $relativePath = $pdf.FullName.Substring($basePathPrefix.Length)
    Write-Host ''
    Write-Host (Get-LocalizedText -Text '--- PDF {0}/{1}: {2} ---' `
                -Arguments @(($index + 1), $pdfFiles.Count, $relativePath) `
                -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan

    $tempStem = '.{0}' -f [guid]::NewGuid().ToString('N')
    $candidatePath = Join-Path $pdf.DirectoryName ($tempStem + '.normalized.pdf.part')
    $replaceBackupPath = Join-Path $pdf.DirectoryName ($tempStem + '.bak.part')
    $originalBackupPath = Join-Path $pdf.DirectoryName ($pdf.BaseName + '_orig' + $pdf.Extension)

    try
    {
        $inspection = Invoke-PdfObjectStreamNormalization -PythonPath $pythonRuntime.Path `
                -InputPath $pdf.FullName -OutputPath $candidatePath -CheckOnly `
                -UiLanguage $OutputLanguage -MessagesPath $MessagesPath

        if ($inspection.Status -eq 'NoTextLayer')
        {
            $reason = Get-LocalizedText 'No text layer found; no changes were made.' -Language $OutputLanguage -MessagesPath $MessagesPath
            Write-Host $reason -ForegroundColor DarkYellow
            [pscustomobject]@{ Status = 'Skipped'; FilePath = $pdf.FullName; Reason = $reason }
            continue
        }
        if ($inspection.Status -eq 'AlreadyNormalized')
        {
            $reason = Get-LocalizedText 'The PDF is already normalized; no changes were made.' -Language $OutputLanguage -MessagesPath $MessagesPath
            Write-Host $reason -ForegroundColor DarkYellow
            [pscustomobject]@{ Status = 'Skipped'; FilePath = $pdf.FullName; Reason = $reason }
            continue
        }
        if ($inspection.Status -eq 'Signed')
        {
            throw (Get-LocalizedText 'Digitally signed PDFs cannot be changed.' -Language $OutputLanguage -MessagesPath $MessagesPath)
        }
        if ($inspection.Status -eq 'Encrypted')
        {
            throw (Get-LocalizedText 'Encrypted PDFs cannot be processed.' -Language $OutputLanguage -MessagesPath $MessagesPath)
        }
        if ($inspection.Status -ne 'NeedsNormalization')
        {
            throw (Get-LocalizedText -Text 'Python returned an invalid object-stream result for ''{0}''.' `
                        -Arguments @($pdf.FullName) -Language $OutputLanguage -MessagesPath $MessagesPath)
        }

        if (-not $PSCmdlet.ShouldProcess(
                $relativePath,
                (Get-LocalizedText 'Normalize PDF object streams' -Language $OutputLanguage -MessagesPath $MessagesPath)
        ))
        {
            Write-Host (Get-LocalizedText 'Preview: PDF object streams would be normalized.' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor DarkYellow
            [pscustomobject]@{ Status = 'Preview'; FilePath = $pdf.FullName; Reason = $null }
            continue
        }

        $normalization = Invoke-PdfObjectStreamNormalization -PythonPath $pythonRuntime.Path `
                -InputPath $pdf.FullName -OutputPath $candidatePath `
                -UiLanguage $OutputLanguage -MessagesPath $MessagesPath

        if ($normalization.Status -eq 'NoTextLayer')
        {
            $reason = Get-LocalizedText 'No text layer found; no changes were made.' -Language $OutputLanguage -MessagesPath $MessagesPath
            Write-Host $reason -ForegroundColor DarkYellow
            [pscustomobject]@{ Status = 'Skipped'; FilePath = $pdf.FullName; Reason = $reason }
            continue
        }
        if ($normalization.Status -eq 'AlreadyNormalized')
        {
            $reason = Get-LocalizedText 'The PDF is already normalized; no changes were made.' -Language $OutputLanguage -MessagesPath $MessagesPath
            Write-Host $reason -ForegroundColor DarkYellow
            [pscustomobject]@{ Status = 'Skipped'; FilePath = $pdf.FullName; Reason = $reason }
            continue
        }
        if ($normalization.Status -eq 'Signed')
        {
            throw (Get-LocalizedText 'Digitally signed PDFs cannot be changed.' -Language $OutputLanguage -MessagesPath $MessagesPath)
        }
        if ($normalization.Status -eq 'Encrypted')
        {
            throw (Get-LocalizedText 'Encrypted PDFs cannot be processed.' -Language $OutputLanguage -MessagesPath $MessagesPath)
        }
        if ($normalization.Status -ne 'Repaired')
        {
            throw (Get-LocalizedText -Text 'Python returned an invalid object-stream result for ''{0}''.' `
                        -Arguments @($pdf.FullName) -Language $OutputLanguage -MessagesPath $MessagesPath)
        }

        $sourceHash = Get-FileSha256 -Path $pdf.FullName
        $resultHash = Get-FileSha256 -Path $candidatePath
        if ($sourceHash -eq $resultHash)
        {
            $reason = Get-LocalizedText 'The PDF is already normalized; no changes were made.' -Language $OutputLanguage -MessagesPath $MessagesPath
            Write-Host $reason -ForegroundColor DarkYellow
            [pscustomobject]@{ Status = 'Skipped'; FilePath = $pdf.FullName; Reason = $reason }
            continue
        }

        if (-not $ReplaceOriginal -and -not (Test-Path -LiteralPath $originalBackupPath))
        {
            [System.IO.File]::Replace($candidatePath, $pdf.FullName, $originalBackupPath)
            Write-Host (Get-LocalizedText -Text 'Original backed up: {0}' -Arguments @($originalBackupPath) `
                    -Language $OutputLanguage -MessagesPath $MessagesPath)
        }
        else
        {
            if (-not $ReplaceOriginal)
            {
                Write-Warning (Get-LocalizedText -Text "Backup '{0}' already exists and will be preserved; replacing the PDF directly." `
                            -Arguments @([System.IO.Path]::GetFileName($originalBackupPath)) `
                            -Language $OutputLanguage -MessagesPath $MessagesPath)
            }
            [System.IO.File]::Replace($candidatePath, $pdf.FullName, $replaceBackupPath)
        }

        Write-Host (Get-LocalizedText -Text 'Repaired ({0} pages; text found on {1} pages).' `
                -Arguments @($normalization.PageCount, $normalization.TextPageCount) `
                -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Green
        [pscustomobject]@{ Status = 'Repaired'; FilePath = $pdf.FullName; Reason = $null }
    }
    catch
    {
        $reason = $_.Exception.Message
        Write-Warning (Get-LocalizedText -Text "Could not repair PDF '{0}':`n{1}" `
                    -Arguments @($relativePath, $reason) -Language $OutputLanguage -MessagesPath $MessagesPath)
        [pscustomobject]@{ Status = 'Failed'; FilePath = $pdf.FullName; Reason = $reason }
    }
    finally
    {
        foreach ($temporaryPath in @($candidatePath, $replaceBackupPath))
        {
            if (Test-Path -LiteralPath $temporaryPath)
            {
                Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
)

$repaired = @($results | Where-Object Status -eq 'Repaired')
$skipped = @($results | Where-Object Status -eq 'Skipped')
$previewed = @($results | Where-Object Status -eq 'Preview')
$failed = @($results | Where-Object Status -eq 'Failed')

Write-Host ''
Write-Host (Get-LocalizedText '=== Summary ===' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Repaired: {0}, skipped: {1}, previewed: {2}, failed: {3}' `
    -Arguments @($repaired.Count, $skipped.Count, $previewed.Count, $failed.Count) `
    -Language $OutputLanguage -MessagesPath $MessagesPath)

Write-Host ''
Write-Host (Get-LocalizedText 'PDFs skipped without changes:' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
if ($skipped.Count -eq 0)
{
    Write-Host (Get-LocalizedText '  None.' -Language $OutputLanguage -MessagesPath $MessagesPath)
}
else
{
    foreach ($result in $skipped)
    {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($relativePath, $result.Reason) `
            -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor DarkYellow
    }
}

Write-Host ''
Write-Host (Get-LocalizedText 'PDFs that could not be repaired:' -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Cyan
if ($failed.Count -eq 0)
{
    Write-Host (Get-LocalizedText '  None.' -Language $OutputLanguage -MessagesPath $MessagesPath)
}
else
{
    foreach ($result in $failed)
    {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($relativePath, $result.Reason) `
            -Language $OutputLanguage -MessagesPath $MessagesPath) -ForegroundColor Yellow
    }
}

if ($failed.Count -gt 0)
{
    exit 1
}
