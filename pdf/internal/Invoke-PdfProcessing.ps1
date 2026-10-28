<#
.SYNOPSIS
    Provides the per-file processing pipeline for the OCR script.

.DESCRIPTION
    Defines Invoke-PdfProcessing, which checks one PDF, runs OCRmyPDF, validates
    the result, and replaces the input.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Uses Get-LocalizedText
    and Get-FileSha256.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Adds OCR and corrects a single scanned PDF.

.DESCRIPTION
    Checks signatures and the text layer, then runs OCRmyPDF when OCR is
    needed. Digitally born PDFs are skipped. Existing OCR text is preserved;
    page rotation is detected separately and applied as PDF page metadata.
    OCRmyPDF skips pages that already have text, while adding OCR to textless
    pages in mixed documents. Encrypted and digitally signed PDFs are reported
    as issues because they cannot be processed.
    The result replaces the input; by default, the original is first saved as
    _orig.pdf. Image optimization is disabled.

    Console output is not written directly. Each message is passed to the
    Reporter scriptblock, which the caller uses to display it.

.PARAMETER Pdf
    Input PDF to process.

.PARAMETER PythonPath
    Path to the Python installation.

.PARAMETER Language
    Tesseract language codes joined with '+'.

.PARAMETER NoDeskew
    Disables deskewing.

.PARAMETER NoRotationOfPages
    Disables detection and correction of rotated pages.

.PARAMETER ReplaceOriginal
    Replaces the input without creating an _orig backup.

.PARAMETER GhostscriptPath
    Path to Ghostscript, used to render pages for orientation detection.

.PARAMETER TesseractPath
    Path to Tesseract, used for orientation detection without OCR.

.PARAMETER UiLanguage
    Language of the messages: 'de' selects the German catalog, anything else English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.PARAMETER Reporter
    Scriptblock that receives console output. It is called as
    & $Reporter 'Host' <ConsoleColor or $null> <text> for regular output and
    & $Reporter 'Warning' $null <text> for warnings. Defaults to discarding output.

.OUTPUTS
    PSCustomObject with Success, Skipped, FilePath, FailureReason, Warning,
    OriginalBytes, and ResultBytes.
#>
function Invoke-PdfProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string] $Language,
        [Parameter(Mandatory)][bool] $NoDeskew,
        [Parameter(Mandatory)][bool] $NoRotationOfPages,
        [Parameter(Mandatory)][bool] $ReplaceOriginal,
        [AllowNull()][string] $GhostscriptPath,
        [AllowNull()][string] $TesseractPath,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{},
        [scriptblock] $Reporter = { }
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }

    # Keep temporary files beside the input so replacement stays on the same volume.
    $tempStem = '.{0}' -f [guid]::NewGuid().ToString('N')
    $tempPath = Join-Path $Pdf.DirectoryName ($tempStem + '.pdf.part')
    $rotationTempPath = Join-Path $Pdf.DirectoryName ($tempStem + '.rotated.pdf.part')
    $originalPath = Join-Path $Pdf.DirectoryName ($Pdf.BaseName + '_orig' + $Pdf.Extension)
    $replaceBackupPath = Join-Path $Pdf.DirectoryName ($tempStem + '.bak.part')
    $signatureCheckPath = Join-Path $Pdf.DirectoryName ($tempStem + '.sig.py.part')
    $backupWarning = $null
    $failureReason = $null
    $failureDetails = $null
    try {
        & $Reporter 'Host' $null (Get-LocalizedText @localization -Text 'Processing: {0}' -Arguments @($Pdf.Name))
        $signatureCheck = @'
import sys
import pikepdf

TEXT_OPERATORS = {"Tj", "TJ", "'", '"'}

def has_signature_value(value):
    return value is not None and "/ByteRange" in value and "/Contents" in value

def field_is_signed(field, inherited_type=None):
    field_type = field.get("/FT", inherited_type)
    if str(field_type) == "/Sig" and has_signature_value(field.get("/V")):
        return True
    return any(field_is_signed(child, field_type) for child in field.get("/Kids", []))

def object_key(obj):
    try:
        object_number, generation = obj.objgen
        if object_number:
            return (object_number, generation)
    except (AttributeError, TypeError):
        pass
    return id(obj)

def inherited_resources(page):
    node = page
    while node is not None:
        resources = node.get("/Resources")
        if resources is not None:
            return resources
        node = node.get("/Parent")
    return pikepdf.Dictionary()

def inspect_stream(stream, resources, visited, features, render_mode=0):
    key = object_key(stream)
    if key in visited:
        return
    visited.add(key)
    xobjects = resources.get("/XObject", {})
    for operands, operator in pikepdf.parse_content_stream(stream):
        operator_name = str(operator)
        if operator_name == "Tr" and operands:
            try:
                render_mode = int(operands[0])
            except (TypeError, ValueError):
                pass
        if operator_name in TEXT_OPERATORS:
            features["has_text"] = True
            if render_mode == 3:
                features["has_hidden_text"] = True
            else:
                features["has_visible_text"] = True
        if operator_name in ("INLINE IMAGE", "BI"):
            features["has_image"] = True
        if operator_name == "Do" and operands:
            child = xobjects.get(operands[0])
            if child is None:
                continue
            subtype = str(child.get("/Subtype"))
            if subtype == "/Image":
                features["has_image"] = True
            elif subtype == "/Form":
                child_resources = child.get("/Resources", resources)
                inspect_stream(child, child_resources, visited, features, render_mode)

try:
    pdf = pikepdf.open(sys.argv[1])
except pikepdf.PasswordError:
    print("ENCRYPTED")
    sys.exit(0)

with pdf:
    if pdf.is_encrypted:
        print("ENCRYPTED")
        sys.exit(0)
    acro_form = pdf.Root.get("/AcroForm")
    fields = acro_form.get("/Fields", []) if acro_form is not None else []
    permissions = pdf.Root.get("/Perms")
    permission_signatures = (
        [permissions.get("/DocMDP"), permissions.get("/UR3")]
        if permissions is not None else []
    )
    signed = any(field_is_signed(field) for field in fields)
    signed = signed or any(has_signature_value(value) for value in permission_signatures)
    page_features = []
    for page in pdf.pages:
        features = {
            "has_text": False,
            "has_visible_text": False,
            "has_hidden_text": False,
            "has_image": False,
        }
        inspect_stream(page, inherited_resources(page.obj), set(), features)
        page_features.append(features)
    text_pages = sum(features["has_text"] for features in page_features)
    visible_text_pages = sum(features["has_visible_text"] for features in page_features)
    scanned_pages = sum(
        features["has_image"] and (
            features["has_hidden_text"] or not features["has_visible_text"]
        )
        for features in page_features
    )
    print(
        f"{'SIGNED' if signed else 'UNSIGNED'}\t{len(pdf.pages)}\t"
        f"{text_pages}\t{visible_text_pages}\t{scanned_pages}"
    )
'@
        [System.IO.File]::WriteAllText($signatureCheckPath, $signatureCheck, [System.Text.UTF8Encoding]::new($false))

        # Keep the signature preflight separate; OCRmyPDF is launched directly below
        # so its native progress display remains visible in the terminal.
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $signatureCheckOutput = @(& $PythonPath $signatureCheckPath $Pdf.FullName 2>&1)
            $signatureCheckExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($signatureCheckExitCode -ne 0) {
            $checkDetails = ($signatureCheckOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
            throw (Get-LocalizedText @localization -Text 'Signature and text-layer check failed (exit code {0}): {1}' -Arguments @($signatureCheckExitCode, $checkDetails))
        }
        $signatureStatus = ($signatureCheckOutput | ForEach-Object { $_.ToString() }) -join ''
        if ($signatureStatus.Trim() -eq 'ENCRYPTED') {
            $failureReason = Get-LocalizedText @localization -Text 'Encrypted PDF'
            & $Reporter 'Warning' $null (Get-LocalizedText @localization -Text "Could not process: '{0}'`nThe PDF is encrypted and will not be processed." -Arguments @($Pdf.Name))
            return [pscustomobject]@{ Success = $false; Skipped = $false; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $null; OriginalBytes = [long]0; ResultBytes = [long]0 }
        }
        $signatureValues = $signatureStatus.Trim() -split "`t"
        if (
            $signatureValues.Count -ne 5 -or
            $signatureValues[0] -notin @('SIGNED', 'UNSIGNED') -or
            $signatureValues[1] -notmatch '^\d+$' -or
            $signatureValues[2] -notmatch '^\d+$' -or
            $signatureValues[3] -notmatch '^\d+$' -or
            $signatureValues[4] -notmatch '^\d+$'
        ) {
            throw (Get-LocalizedText @localization -Text "Signature and text-layer check returned an invalid result: '{0}'" -Arguments @($signatureStatus))
        }
        $signatureStatus = $signatureValues[0]
        $pageCount = [int]$signatureValues[1]
        $textPageCount = [int]$signatureValues[2]
        $visibleTextPageCount = [int]$signatureValues[3]
        $scannedPageCount = [int]$signatureValues[4]
        if ($pageCount -eq 0) {
            throw (Get-LocalizedText @localization -Text 'The PDF file contains no pages.')
        }
        $isDigitallyBorn = $visibleTextPageCount -gt 0 -and $scannedPageCount -eq 0
        if ($signatureStatus -eq 'SIGNED') {
            $failureReason = Get-LocalizedText @localization -Text 'Digitally signed PDF'
            $failureDetails = Get-LocalizedText @localization -Text 'The input PDF has a digital signature. OCR would alter the document and invalidate the signature.'
            & $Reporter 'Warning' $null (Get-LocalizedText @localization -Text "Could not process: '{0}'`n{1}" -Arguments @($Pdf.Name, $failureDetails))
            return [pscustomobject]@{ Success = $false; Skipped = $false; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $null; OriginalBytes = [long]0; ResultBytes = [long]0 }
        }

        if ($isDigitallyBorn)
        {
            $failureReason = Get-LocalizedText @localization -Text 'Digitally born PDF; skipped by default'
            & $Reporter 'Host' 'Green' (Get-LocalizedText @localization -Text 'This PDF appears digitally born; skipping it.')
            return [pscustomobject]@{ Success = $false; Skipped = $true; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $null; OriginalBytes = [long]0; ResultBytes = [long]0 }
        }

        if (-not $ReplaceOriginal -and (Test-Path -LiteralPath $originalPath)) {
            $relativeOriginalPath = $originalPath.Substring($Pdf.DirectoryName.Length + 1)
            $backupWarning = Get-LocalizedText @localization -Text 'Backup already exists'
            & $Reporter 'Warning' $null (Get-LocalizedText @localization -Text "Backup '{0}' already exists and will be preserved; replacing the PDF directly." -Arguments @($relativeOriginalPath))
        }

        $hasExistingText = $textPageCount -gt 0
        $shouldRunOcr = $true
        $processingInputPath = $Pdf.FullName
        $resultPath = $tempPath
        $changedRotationPages = 0
        if ($hasExistingText)
        {
            & $Reporter 'Host' 'Yellow' (Get-LocalizedText @localization -Text 'Existing OCR text will be preserved; page rotation is detected without running OCR.')
            if (-not $NoRotationOfPages)
            {
                if ($GhostscriptPath -and $TesseractPath)
                {
                    $rotationResult = Invoke-PdfRotationOnly -Pdf $Pdf -PageCount $pageCount `
                        -PythonPath $PythonPath -GhostscriptPath $GhostscriptPath -TesseractPath $TesseractPath `
                        -OutputPath $rotationTempPath -ConfidenceThreshold 5 `
                        -UiLanguage $UiLanguage -Messages $Messages
                    $changedRotationPages = $rotationResult.ChangedPages.Count
                    if ($changedRotationPages -gt 0)
                    {
                        $processingInputPath = $rotationTempPath
                    }
                    if ($rotationResult.UndeterminedPages.Count -gt 0)
                    {
                        & $Reporter 'Warning' $null (Get-LocalizedText @localization -Text 'Orientation could not be determined for pages: {0}; those pages were left unchanged.' -Arguments @(($rotationResult.UndeterminedPages -join ', ')))
                    }
                }
                else
                {
                    $rotationWarning = Get-LocalizedText @localization -Text 'Ghostscript is unavailable; page rotation could not be checked for this PDF.'
                    $backupWarning = if ($backupWarning)
                    {
                        $backupWarning + ' ' + $rotationWarning
                    }
                    else
                    {
                        $rotationWarning
                    }
                    & $Reporter 'Warning' $null $rotationWarning
                }
            }

            if ($textPageCount -eq $pageCount)
            {
                $shouldRunOcr = $false
                $resultPath = $rotationTempPath
                if ($changedRotationPages -eq 0)
                {
                    $failureReason = Get-LocalizedText @localization -Text 'Existing OCR was preserved; no page rotation was applied.'
                    & $Reporter 'Host' 'Yellow' $failureReason
                    return [pscustomobject]@{ Success = $false; Skipped = $true; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $backupWarning; OriginalBytes = [long]0; ResultBytes = [long]0 }
                }
            }
        }

        if ($shouldRunOcr)
        {
            $ocrArguments = @(
                '-m', 'ocrmypdf',
                '--output-type', 'pdf',
                '--optimize', '0',
                '--language', $Language,
                '--skip-text'
            )
            if (-not $NoDeskew)
            {
                $ocrArguments += '--deskew'
            }
            if (-not $NoRotationOfPages -and -not $hasExistingText)
            {
                $ocrArguments += @('--rotate-pages', '--rotate-pages-threshold', '5')
            }
            $ocrArguments += @($processingInputPath, $tempPath)

            # Do not redirect streams: preserve OCRmyPDF's native progress display.
            $previousErrorActionPreference = $ErrorActionPreference
            try
            {
                $ErrorActionPreference = 'Continue'
                & $PythonPath @ocrArguments
                $ocrExitCode = $LASTEXITCODE
            }
            finally
            {
                $ErrorActionPreference = $previousErrorActionPreference
            }
            if ($ocrExitCode -ne 0 -or -not (Test-Path -LiteralPath $tempPath))
            {
                $failureReason = Get-LocalizedText @localization -Text 'OCRmyPDF error (exit code {0})' -Arguments @($ocrExitCode)
                $failureDetails = Get-LocalizedText @localization -Text '{0}. See the OCRmyPDF console output for details.' -Arguments @($failureReason)
                throw $failureDetails
            }
        }
        else
        {
            $resultPath = $rotationTempPath
        }

        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf))
        {
            throw (Get-LocalizedText @localization 'The processing step did not produce an output PDF.')
        }
        $originalSize = (Get-Item -LiteralPath $Pdf.FullName).Length
        $resultSize = (Get-Item -LiteralPath $resultPath).Length

        # An identical hash means no change occurred and the run failed.
        $originalHash = Get-FileSha256 -Path $Pdf.FullName
        $resultHash = Get-FileSha256 -Path $resultPath
        if ($originalHash -eq $resultHash) {
            & $Reporter 'Host' 'Yellow' (Get-LocalizedText @localization -Text 'The result is identical to the original (no changes); discarding the output.')
            return [pscustomobject]@{ Success = $false; Skipped = $true; FilePath = $Pdf.FullName; FailureReason = (Get-LocalizedText @localization -Text 'No changes'); Warning = $backupWarning; OriginalBytes = [long]$originalSize; ResultBytes = [long]0 }
        }

        # Replace the input only after successful processing and hash validation.
        if (-not $ReplaceOriginal -and -not (Test-Path -LiteralPath $originalPath)) {
            [System.IO.File]::Replace($resultPath, $Pdf.FullName, $originalPath)
            & $Reporter 'Host' $null (Get-LocalizedText @localization -Text 'Original backed up: {0}' -Arguments @($originalPath))
        }
        else {
            [System.IO.File]::Replace($resultPath, $Pdf.FullName, $replaceBackupPath)
        }
        if ($resultSize -lt $originalSize) {
            & $Reporter 'Host' 'Green' (Get-LocalizedText @localization -Text 'Optimized: {0:N1} MB -> {1:N1} MB' -Arguments @(($originalSize / 1MB), ($resultSize / 1MB)))
        }
        else {
            & $Reporter 'Host' 'Cyan' (Get-LocalizedText @localization -Text 'Processed (larger than original): {0:N1} MB -> {1:N1} MB' -Arguments @(($originalSize / 1MB), ($resultSize / 1MB)))
        }
        & $Reporter 'Host' $null (Get-LocalizedText @localization -Text 'Saved: {0}' -Arguments @($Pdf.FullName))
        return [pscustomobject]@{ Success = $true; Skipped = $false; FilePath = $Pdf.FullName; FailureReason = $null; Warning = $backupWarning; OriginalBytes = [long]$originalSize; ResultBytes = [long]$resultSize }
    }
    catch {
        if (-not $failureDetails) { $failureDetails = $_.Exception.Message }
        & $Reporter 'Warning' $null (Get-LocalizedText @localization -Text "Error processing '{0}':`n{1}" -Arguments @($Pdf.Name, $failureDetails))
        if (-not $failureReason) {
            $failureReason = $failureDetails -split '[\r\n]' | Select-Object -First 1
        }
        return [pscustomobject]@{ Success = $false; Skipped = $false; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $backupWarning; OriginalBytes = [long]0; ResultBytes = [long]0 }
    }
    finally {
        # Always remove temporary files, including after failures.
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $rotationTempPath)
        {
            Remove-Item -LiteralPath $rotationTempPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $replaceBackupPath) {
            Remove-Item -LiteralPath $replaceBackupPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $signatureCheckPath) {
            Remove-Item -LiteralPath $signatureCheckPath -Force -ErrorAction SilentlyContinue
        }
    }
}
