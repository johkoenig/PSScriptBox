<#
.SYNOPSIS
    Detects and applies PDF page rotations without running OCR.

.DESCRIPTION
    Renders PDF pages with Ghostscript, asks Tesseract for orientation only,
    and updates the PDF page rotation with pikepdf. Existing page content,
    including OCR text, is not rasterized or regenerated.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7, Ghostscript,
    Tesseract with osd data, and Python with pikepdf. Uses Invoke-SetupProcess
    and Invoke-PythonCommand.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Detects and applies PDF page rotations without running OCR.

.DESCRIPTION
    Renders PDF pages with Ghostscript, asks Tesseract for orientation only,
    and updates the PDF page rotation with pikepdf. Existing page content,
    including OCR text, is not rasterized or regenerated.

.PARAMETER Pdf
    Input PDF to inspect.

.PARAMETER PageCount
    Expected number of PDF pages.

.PARAMETER PythonPath
    Path to the Python interpreter with pikepdf.

.PARAMETER GhostscriptPath
    Path to the Ghostscript console executable.

.PARAMETER TesseractPath
    Path to the Tesseract executable.

.PARAMETER OutputPath
    Path where the rotated PDF is written when a rotation is detected.

.PARAMETER ConfidenceThreshold
    Minimum Tesseract orientation confidence required to rotate a page.

.PARAMETER UiLanguage
    'de' selects German messages; anything else selects English.

.PARAMETER Messages
    German catalog keyed by the English source text.

.OUTPUTS
    PSCustomObject with ChangedPages and UndeterminedPages.
#>
function Invoke-PdfRotationOnly
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][ValidateRange(1, 100000)][int] $PageCount,
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string] $GhostscriptPath,
        [Parameter(Mandatory)][string] $TesseractPath,
        [Parameter(Mandatory)][string] $OutputPath,
        [ValidateRange(0, 100)][double] $ConfidenceThreshold = 5,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{ }
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }
    $temporaryDirectory = Join-Path $Pdf.DirectoryName ('.{0}.orientation.part' -f [guid]::NewGuid().ToString('N'))
    $renderPattern = Join-Path $temporaryDirectory 'page-%d.png.part'
    $rotationChanges = [System.Collections.Generic.List[object]]::new()
    $undeterminedPages = [System.Collections.Generic.List[int]]::new()

    New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null
    try
    {
        $renderArguments = @(
            '-dSAFER',
            '-dBATCH',
            '-dNOPAUSE',
            '-dQUIET',
            '-dAutoRotatePages=/None',
            '-sDEVICE=pnggray',
            '-r150',
            '-dTextAlphaBits=4',
            ('-sOutputFile={0}' -f $renderPattern),
            $Pdf.FullName
        )
        $renderResult = Invoke-SetupProcess -FilePath $GhostscriptPath -Arguments $renderArguments `
            -UiLanguage $UiLanguage -Messages $Messages
        if ($renderResult.ExitCode -ne 0)
        {
            $renderDetails = if ($renderResult.StdErr)
            {
                $renderResult.StdErr.Trim()
            }
            else
            {
                $renderResult.StdOut.Trim()
            }
            throw (Get-LocalizedText @localization -Text 'Ghostscript rotation analysis failed (exit code {0}): {1}' -Arguments @($renderResult.ExitCode, $renderDetails))
        }

        $pageImages = @(
        Get-ChildItem -LiteralPath $temporaryDirectory -Filter 'page-*.png.part' -File |
                Sort-Object { [int]([regex]::Match($_.Name, '^page-(\d+)\.png\.part$').Groups[1].Value) }
        )
        if ($pageImages.Count -ne $PageCount)
        {
            throw (Get-LocalizedText -Text 'Ghostscript rendered {0} of {1} pages for rotation analysis.' -Arguments @($pageImages.Count, $PageCount))
        }

        foreach ($pageImage in $pageImages)
        {
            $pageNumber = [int]([regex]::Match($pageImage.Name, '^page-(\d+)\.png\.part$').Groups[1].Value)
            $orientationResult = Invoke-SetupProcess -FilePath $TesseractPath `
                -Arguments @($pageImage.FullName, 'stdout', '-l', 'osd', '--psm', '0') `
                -UiLanguage $UiLanguage -Messages $Messages

            $orientationText = @($orientationResult.StdOut, $orientationResult.StdErr) -join "`n"
            $rotationMatch = [regex]::Match($orientationText, '(?m)^Rotate:\s*(\d+)\s*$')
            if ($orientationResult.ExitCode -ne 0)
            {
                if ($orientationText -match '(?i)too few characters|empty page')
                {
                    $undeterminedPages.Add($pageNumber)
                    continue
                }
                throw (Get-LocalizedText -Text 'Tesseract orientation check failed for page {0}: {1}' -Arguments @($pageNumber,$orientationText.Trim()))
            }
            if (-not $rotationMatch.Success)
            {
                $undeterminedPages.Add($pageNumber)
                continue
            }

            $confidenceMatch = [regex]::Match($orientationText, '(?m)^Orientation confidence:\s*([+-]?[0-9]+(?:\.[0-9]+)?)\s*$')
            if (-not $confidenceMatch.Success)
            {
                throw (Get-LocalizedText -Text 'Tesseract returned no orientation confidence for page {0}.' -Arguments @($pageNumber))
            }
            $confidence = [double]::Parse($confidenceMatch.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
            $rotation = [int]$rotationMatch.Groups[1].Value
            if ($rotation -notin @(0, 90, 180, 270))
            {
                throw (Get-LocalizedText -Text 'Tesseract returned an invalid rotation for page {0}: {1}' -Arguments @($pageNumber, $rotation))
            }
            if ($confidence -lt $ConfidenceThreshold)
            {
                $undeterminedPages.Add($pageNumber)
                continue
            }
            if ($rotation -ne 0)
            {
                $rotationChanges.Add([pscustomobject]@{
                    PageNumber = $pageNumber
                    Rotation = $rotation
                })
            }
        }

        if ($rotationChanges.Count -eq 0)
        {
            return [pscustomobject]@{
                ChangedPages = @()
                UndeterminedPages = @($undeterminedPages)
            }
        }

        $pythonCode = @'
import json
import sys
import pikepdf

input_path, output_path, changes_json, expected_pages = sys.argv[1:5]
changes = json.loads(changes_json)
with pikepdf.open(input_path) as pdf:
    if len(pdf.pages) != int(expected_pages):
        raise ValueError("The PDF page count changed during rotation analysis.")
    for change in changes:
        pdf.pages[int(change["PageNumber"]) - 1].rotate(int(change["Rotation"]), relative=True)
    pdf.save(output_path)
'@
        $rotationJson = ConvertTo-Json -InputObject @($rotationChanges) -Compress
        $writeResult = Invoke-PythonCommand -PythonPath $PythonPath `
            -Arguments @('-c', $pythonCode, $Pdf.FullName, $OutputPath, $rotationJson, [string]$PageCount) `
            -UiLanguage $UiLanguage -Messages $Messages
        if ($writeResult.ExitCode -ne 0)
        {
            $writeDetails = if ($writeResult.StdErr)
            {
                $writeResult.StdErr.Trim()
            }
            else
            {
                $writeResult.StdOut.Trim()
            }
            throw (Get-LocalizedText -Text 'Could not apply detected page rotations (exit code {0}): {1}' -Arguments @($writeResult.ExitCode, $writeDetails))
        }
        if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf))
        {
            throw (Get-LocalizedText 'Python did not produce the rotated PDF.')
        }

        return [pscustomobject]@{
            ChangedPages = @($rotationChanges | ForEach-Object { $_.PageNumber })
            UndeterminedPages = @($undeterminedPages)
        }
    }
    finally
    {
        if (Test-Path -LiteralPath $temporaryDirectory)
        {
            Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
