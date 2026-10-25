<#
.SYNOPSIS
    Provides the per-file processing pipeline for the OCR script.

.DESCRIPTION
    Defines Invoke-PdfProcessing, which checks one PDF, runs OCRmyPDF, applies the
    optional Ghostscript stage, validates the result, and replaces the input.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Uses Get-LocalizedText,
    ConvertTo-QuotedArgument, Optimize-WithGhostscript, and Get-FileSha256.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Processes and optimizes a single PDF file.

.DESCRIPTION
    Checks signatures and the text layer, runs OCRmyPDF, and optionally applies
    Ghostscript optimization. Digitally born PDFs are skipped by default;
    scanned     PDFs with existing OCR are automatically reprocessed so deskew and rotation
    can run. Encrypted and digitally signed PDFs are skipped.
    The result replaces the input; by default, the original is first saved as
    _orig.pdf. --optimize 1 avoids the optional jbig2 dependency.

    Console output is not written directly. Each message is passed to the
    Reporter scriptblock, which the caller uses to display it.

.PARAMETER Pdf
    Input PDF to process.

.PARAMETER PythonPath
    Path to the Python installation.

.PARAMETER Language
    Tesseract language codes joined with '+'.

.PARAMETER Quality
    JPEG quality for OCRmyPDF.

.PARAMETER GhostscriptDpi
    Target resolution for optional Ghostscript optimization. 0 disables it.

.PARAMETER NoDeskew
    Disables deskewing.

.PARAMETER NoRotationOfPages
    Disables detection and correction of rotated pages.

.PARAMETER ProcessDigitallyBornPdfs
    Processes PDFs classified as digitally born.

.PARAMETER NoGhostscript
    Disables Ghostscript.

.PARAMETER ReplaceOriginal
    Replaces the input without creating an _orig backup.

.PARAMETER ForceReprocess
    Explicitly reprocesses eligible PDFs. Scanned PDFs with existing text are
    already reprocessed by default.

.PARAMETER GhostscriptPath
    Path to Ghostscript, if available.

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
        [Parameter(Mandatory)][int] $Quality,
        [Parameter(Mandatory)][int] $GhostscriptDpi,
        [Parameter(Mandatory)][bool] $NoDeskew,
        [Parameter(Mandatory)][bool] $NoRotationOfPages,
        [Parameter(Mandatory)][bool] $ProcessDigitallyBornPdfs,
        [Parameter(Mandatory)][bool] $NoGhostscript,
        [Parameter(Mandatory)][bool] $ReplaceOriginal,
        [Parameter(Mandatory)][bool] $ForceReprocess,
        [string] $GhostscriptPath,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{},
        [scriptblock] $Reporter = { param($Kind, $Color, $Text) }
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }

    # Keep temporary files beside the input so replacement stays on the same volume.
    $tempStem = '.{0}' -f [guid]::NewGuid().ToString('N')
    $tempPath = Join-Path $Pdf.DirectoryName ($tempStem + '.pdf.part')
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
            $failureReason = Get-LocalizedText @localization -Text 'Encrypted (password required)'
            & $Reporter 'Warning' $null (Get-LocalizedText @localization -Text "Skipped: '{0}'`nThe PDF is encrypted and cannot be processed without a password." -Arguments @($Pdf.Name))
            return [pscustomobject]@{ Success = $false; Skipped = $true; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $null; OriginalBytes = [long]0; ResultBytes = [long]0 }
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
            & $Reporter 'Warning' $null (Get-LocalizedText @localization -Text "Skipped: '{0}'`n{1}" -Arguments @($Pdf.Name, $failureDetails))
            return [pscustomobject]@{ Success = $false; Skipped = $true; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $null; OriginalBytes = [long]0; ResultBytes = [long]0 }
        }

        if ($isDigitallyBorn -and -not $ProcessDigitallyBornPdfs) {
            $failureReason = Get-LocalizedText @localization -Text 'Digitally born PDF; skipped by default'
            & $Reporter 'Host' 'Green' (Get-LocalizedText @localization -Text 'This PDF appears digitally born; skipping it. Use -ProcessDigitallyBornPdfs to process it.')
            return [pscustomobject]@{ Success = $false; Skipped = $true; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $null; OriginalBytes = [long]0; ResultBytes = [long]0 }
        }

        if (-not $ReplaceOriginal -and (Test-Path -LiteralPath $originalPath)) {
            $relativeOriginalPath = $originalPath.Substring($Pdf.DirectoryName.Length + 1)
            $backupWarning = Get-LocalizedText @localization -Text 'Backup already exists'
            & $Reporter 'Warning' $null (Get-LocalizedText @localization -Text "Backup '{0}' already exists and will be preserved; replacing the PDF directly." -Arguments @($relativeOriginalPath))
        }

        $rebuildOcr = $textPageCount -gt 0 -and (-not $isDigitallyBorn -or $ForceReprocess)
        if ($rebuildOcr) {
            & $Reporter 'Host' 'Yellow' (Get-LocalizedText @localization -Text 'Existing OCR text will be rebuilt so deskew and rotation correction can run; repeated runs may change the PDF again.')
        }

        $ocrArguments = @(
            '-m', 'ocrmypdf',
            '--output-type', 'pdf',
            '--optimize', '1',
            '--jpeg-quality', "$Quality",
            '--language', $Language
        )
        if ($rebuildOcr) {
            $ocrArguments += '--force-ocr'
        }
        else {
            $ocrArguments += '--skip-text'
        }
        if (-not $NoDeskew) { $ocrArguments += '--deskew' }
        if (-not $NoRotationOfPages) { $ocrArguments += @('--rotate-pages', '--rotate-pages-threshold', '5') }
        $ocrArguments += @($Pdf.FullName, $tempPath)

        # Do not redirect streams: preserve OCRmyPDF's native console output and progress display.
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $PythonPath @ocrArguments
            $ocrExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($ocrExitCode -ne 0 -or -not (Test-Path -LiteralPath $tempPath)) {
            $failureReason = Get-LocalizedText @localization -Text 'OCRmyPDF error (exit code {0})' -Arguments @($ocrExitCode)
            $failureDetails = Get-LocalizedText @localization -Text '{0}. See the OCRmyPDF console output for details.' -Arguments @($failureReason)
            throw $failureDetails
        }

        # Run Ghostscript only when a target resolution is specified and the
        # executable is available. Accept its result only when it is smaller.
        if (-not $NoGhostscript -and $GhostscriptDpi -gt 0 -and $GhostscriptPath) {
            $gsResult = Get-Item -LiteralPath $tempPath
            Optimize-WithGhostscript -GhostscriptPath $GhostscriptPath -Pdf $gsResult -Dpi $GhostscriptDpi | Out-Null
        }

        $originalSize = (Get-Item -LiteralPath $Pdf.FullName).Length
        $resultSize = (Get-Item -LiteralPath $tempPath).Length

        # An identical hash means no change occurred and the run failed.
        # A larger but changed result is still a successful transformation.
        $originalHash = Get-FileSha256 -Path $Pdf.FullName
        $resultHash = Get-FileSha256 -Path $tempPath
        if ($originalHash -eq $resultHash) {
            & $Reporter 'Host' 'Yellow' (Get-LocalizedText @localization -Text 'The result is identical to the original (no changes); discarding the output.')
            return [pscustomobject]@{ Success = $false; Skipped = $false; FilePath = $Pdf.FullName; FailureReason = (Get-LocalizedText @localization -Text 'No changes'); Warning = $backupWarning; OriginalBytes = [long]$originalSize; ResultBytes = [long]0 }
        }

        # Replace the input only after successful processing and hash validation.
        if (-not $ReplaceOriginal -and -not (Test-Path -LiteralPath $originalPath)) {
            [System.IO.File]::Replace($tempPath, $Pdf.FullName, $originalPath)
            & $Reporter 'Host' $null (Get-LocalizedText @localization -Text 'Original backed up: {0}' -Arguments @($originalPath))
        }
        else {
            [System.IO.File]::Replace($tempPath, $Pdf.FullName, $replaceBackupPath)
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
        if (Test-Path -LiteralPath $replaceBackupPath) {
            Remove-Item -LiteralPath $replaceBackupPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $signatureCheckPath) {
            Remove-Item -LiteralPath $signatureCheckPath -Force -ErrorAction SilentlyContinue
        }
    }
}
