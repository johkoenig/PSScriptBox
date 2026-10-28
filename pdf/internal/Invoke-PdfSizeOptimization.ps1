<#
.SYNOPSIS
    Provides per-file PDF size optimization.

.DESCRIPTION
    Defines Invoke-PdfSizeOptimization, which reports encrypted and signed PDFs
    as issues, downsamples images with Ghostscript, and replaces the input only
    when the result is smaller.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7, Python, pikepdf, and
    Ghostscript. Uses Get-LocalizedText and Optimize-WithGhostscript.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Reduces the size of a single PDF when Ghostscript produces a smaller result.

.DESCRIPTION
    Checks for encryption and digital signatures before optimizing images.
    The input is replaced only when the optimized output is smaller. By default,
    an _orig backup is created and existing backups are preserved.

.PARAMETER Pdf
    Input PDF to process.

.PARAMETER PythonPath
    Path to the Python installation containing pikepdf.

.PARAMETER GhostscriptPath
    Path to the Ghostscript executable.

.PARAMETER Dpi
    Target image resolution.

.PARAMETER Quality
    JPEG quality for downsampled images.

.PARAMETER MinFileSize
    Minimum original file size in bytes for processing. Defaults to 1 MB.

.PARAMETER ReplaceOriginal
    Replaces the input without creating an _orig backup.

.PARAMETER UiLanguage
    Language of the messages: 'de' selects the German catalog, anything else English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.PARAMETER Reporter
    Receives regular and warning messages for display by the caller.

.OUTPUTS
    PSCustomObject with Success, Skipped, FilePath, FailureReason, Warning,
    OriginalBytes, and ResultBytes.
#>
function Invoke-PdfSizeOptimization
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string] $GhostscriptPath,
        [Parameter(Mandatory)][int] $Dpi,
        [Parameter(Mandatory)][int] $Quality,
        [ValidateScript({ $_ -ge 0 })]
        [long] $MinFileSize = 1MB,
        [Parameter(Mandatory)][bool] $ReplaceOriginal,
        [string] $UiLanguage = 'en',
        [string]$MessagesPath = '',
        [scriptblock] $Reporter = { }
    )
    $tempStem = '.{0}' -f [guid]::NewGuid().ToString('N')
    $candidatePath = Join-Path $Pdf.DirectoryName ($tempStem + '.pdf.part')
    $checkPath = Join-Path $Pdf.DirectoryName ($tempStem + '.check.py.part')
    $replaceBackupPath = Join-Path $Pdf.DirectoryName ($tempStem + '.bak.part')
    $originalPath = Join-Path $Pdf.DirectoryName ($Pdf.BaseName + '_orig' + $Pdf.Extension)
    $backupWarning = $null
    $failureReason = $null

    try
    {
        $originalSize = (Get-Item -LiteralPath $Pdf.FullName).Length
        if ($originalSize -lt $MinFileSize)
        {
            $failureReason = Get-LocalizedText -Text 'Below minimum file size: {0:N2} MB' -Arguments @(($MinFileSize / 1MB)) -Language $UiLanguage -MessagesPath $MessagesPath
            & $Reporter 'Host' 'DarkYellow' (Get-LocalizedText -Text 'The original is smaller than the minimum size ({0:N2} MB); skipping it.' -Arguments @(($MinFileSize / 1MB)) -Language $UiLanguage -MessagesPath $MessagesPath)
            return [pscustomobject]@{ Success = $false; Skipped = $true; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $null; OriginalBytes = [long]0; ResultBytes = [long]0 }
        }

        & $Reporter 'Host' $null (Get-LocalizedText -Text 'Processing: {0}' -Arguments @($Pdf.Name) -Language $UiLanguage -MessagesPath $MessagesPath)
        $checkScript = @'
import sys
import pikepdf

def has_signature_value(value):
    return value is not None and "/ByteRange" in value and "/Contents" in value

def field_is_signed(field, inherited_type=None):
    field_type = field.get("/FT", inherited_type)
    if str(field_type) == "/Sig" and has_signature_value(field.get("/V")):
        return True
    return any(field_is_signed(child, field_type) for child in field.get("/Kids", []))

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
    print("SIGNED" if signed else "UNSIGNED")
'@
        [System.IO.File]::WriteAllText($checkPath, $checkScript,[System.Text.UTF8Encoding]::new($false))

        $previousErrorActionPreference = $ErrorActionPreference
        try
        {
            $ErrorActionPreference = 'Continue'
            $checkOutput = @(& $PythonPath $checkPath $Pdf.FullName 2>&1)
            $checkExitCode = $LASTEXITCODE
        }
        finally
        {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($checkExitCode -ne 0)
        {
            $details = ($checkOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
            throw (Get-LocalizedText -Text 'PDF protection check failed (exit code {0}): {1}' -Arguments @($checkExitCode, $details) -Language $UiLanguage -MessagesPath $MessagesPath)
        }

        $protection = ($checkOutput | ForEach-Object { $_.ToString() }) -join ''
        if ($protection.Trim() -eq 'ENCRYPTED')
        {
            $failureReason = Get-LocalizedText -Text 'Encrypted PDF' -Language $UiLanguage -MessagesPath $MessagesPath
            & $Reporter 'Warning' $null (Get-LocalizedText -Text "Could not process: '{0}'`nThe PDF is encrypted and will not be processed." -Arguments @($Pdf.Name) -Language $UiLanguage -MessagesPath $MessagesPath)
            return [pscustomobject]@{ Success = $false; Skipped = $false; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $null; OriginalBytes = [long]0; ResultBytes = [long]0 }
        }
        if ($protection.Trim() -eq 'SIGNED')
        {
            $failureReason = Get-LocalizedText -Text 'Digitally signed PDF' -Language $UiLanguage -MessagesPath $MessagesPath
            & $Reporter 'Warning' $null (Get-LocalizedText -Text "Could not process: '{0}'`nThe input PDF has a digital signature. PDF size optimization would alter the document and invalidate the signature." -Arguments @($Pdf.Name) -Language $UiLanguage -MessagesPath $MessagesPath)
            return [pscustomobject]@{ Success = $false; Skipped = $false; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $null; OriginalBytes = [long]0; ResultBytes = [long]0 }
        }
        if ($protection.Trim() -ne 'UNSIGNED')
        {
            throw (Get-LocalizedText -Text "PDF protection check returned an invalid result: '{0}'" -Arguments @($protection) -Language $UiLanguage -MessagesPath $MessagesPath)
        }

        Copy-Item -LiteralPath $Pdf.FullName -Destination $candidatePath
        $originalSize = (Get-Item -LiteralPath $Pdf.FullName).Length
        $candidate = Get-Item -LiteralPath $candidatePath
        $reduced = Optimize-WithGhostscript -GhostscriptPath $GhostscriptPath -Pdf $candidate -Dpi $Dpi -Quality $Quality
        if (-not $reduced)
        {
            $failureReason = Get-LocalizedText -Text 'No size reduction' -Language $UiLanguage -MessagesPath $MessagesPath
            & $Reporter 'Host' 'Yellow' (Get-LocalizedText -Text 'Ghostscript did not produce a smaller PDF; the original was left unchanged.' -Language $UiLanguage -MessagesPath $MessagesPath)
            return [pscustomobject]@{ Success = $false; Skipped = $true; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $backupWarning; OriginalBytes = [long]0; ResultBytes = [long]0 }
        }

        if (-not $ReplaceOriginal -and (Test-Path -LiteralPath $originalPath))
        {
            $backupWarning = Get-LocalizedText -Text 'Backup already exists' -Language $UiLanguage -MessagesPath $MessagesPath
            & $Reporter 'Warning' $null (Get-LocalizedText -Text "Backup '{0}' already exists and will be preserved; replacing the PDF directly." -Arguments @([System.IO.Path]::GetFileName($originalPath)) -Language $UiLanguage -MessagesPath $MessagesPath)
        }
        $resultSize = (Get-Item -LiteralPath $candidatePath).Length
        if (-not $ReplaceOriginal -and -not (Test-Path -LiteralPath $originalPath))
        {
            [System.IO.File]::Replace($candidatePath, $Pdf.FullName, $originalPath)
            & $Reporter 'Host' $null (Get-LocalizedText -Text 'Original backed up: {0}' -Arguments @($originalPath) -Language $UiLanguage -MessagesPath $MessagesPath)
        }
        else
        {
            [System.IO.File]::Replace($candidatePath, $Pdf.FullName, $replaceBackupPath)
        }
        & $Reporter 'Host' 'Green' (Get-LocalizedText -Text 'Optimized: {0:N1} MB -> {1:N1} MB' -Arguments @(($originalSize / 1MB), ($resultSize / 1MB)) -Language $UiLanguage -MessagesPath $MessagesPath)
        & $Reporter 'Host' $null (Get-LocalizedText -Text 'Saved: {0}' -Arguments @($Pdf.FullName) -Language $UiLanguage -MessagesPath $MessagesPath)
        return [pscustomobject]@{ Success = $true; Skipped = $false; FilePath = $Pdf.FullName; FailureReason = $null; Warning = $backupWarning; OriginalBytes = [long]$originalSize; ResultBytes = [long]$resultSize }
    }
    catch
    {
        $errorDetails = $_.Exception.Message
        $failureReason = $errorDetails -split '[\r\n]' | Select-Object -First 1
        & $Reporter 'Warning' $null (Get-LocalizedText -Text "Error processing '{0}':`n{1}" -Arguments @($Pdf.Name, $errorDetails) -Language $UiLanguage -MessagesPath $MessagesPath)
        return [pscustomobject]@{ Success = $false; Skipped = $false; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $backupWarning; OriginalBytes = [long]0; ResultBytes = [long]0 }
    }
    finally
    {
        foreach ($temporaryPath in @($candidatePath, $checkPath, $replaceBackupPath))
        {
            if (Test-Path -LiteralPath $temporaryPath)
            {
                Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
