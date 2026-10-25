<#
.SYNOPSIS
    Optimizes PDFs with OCR, scan deskewing, and optional compression.

.DESCRIPTION
    Processes one PDF file or all PDF files in a specified folder and its
    subfolders. OCRmyPDF adds a text layer when needed and deskews scans;
    Ghostscript can optionally compress images further. On success, the input
    file is replaced. By default, the original is saved as <Name>_orig.pdf. If
    that backup already exists, it is preserved and the input is replaced
    directly with a warning. -ReplaceOriginal replaces the input without a
    backup. Digitally signed PDFs and encrypted PDFs that cannot be opened
    without a password are skipped before OCR.

    PDFs with text operators on every page are processed with OCRmyPDF's
    skip-text mode by default: OCR is skipped, but PDF optimization and the
    optional Ghostscript stage still run. OCRmyPDF does not apply deskew/rotation
    preprocessing to skipped pages. -RedoOcr reprocesses existing OCR text
    with OCRmyPDF's `--redo-ocr` mode while preserving visible text and vectors.

    TWO-STAGE PROCESSING:
      1. OCRmyPDF adds an OCR text layer and deskews scans. Output is a standard
         PDF (version 1.5), not a PDF/A archive.
      2. Optional Ghostscript downsamples images and embeds them as JPEG. This
         stage runs only when -GhostscriptDpi is explicitly specified (for
         example, -GhostscriptDpi 150). The intermediate result is replaced
         only if Ghostscript makes it smaller.

    DESKEWING:
      - Skewed scans are automatically deskewed (`--deskew`, enabled by default).
      - Rotated pages (90°, 180°, 270°) are not corrected by default. -RotatePages
        enables detection with an OCRmyPDF confidence threshold of 5.

    LANGUAGES:
      The default sequence is 'deu+eng+fra+ita+spa'. German (deu) and English
      (eng) are required. Other languages are optional and are removed if
      unavailable. No interactive language prompt is used.

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
    Default: 'deu+eng+fra+ita+spa'. deu and eng are required; unavailable
    optional languages are removed.

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

.PARAMETER RotatePages
    Enables automatic correction of rotated pages (90°, 180°, 270°). Default:
    $false. A confidence threshold of 5 is used when enabled.

.PARAMETER NoGhostscript
    Disables Ghostscript as a post-processing optimization stage. Ghostscript is
    allowed by default but runs only with -GhostscriptDpi > 0.

.PARAMETER ReplaceOriginal
    Replaces the input without a backup. By default, the original is saved as
    <Name>_orig.pdf after successful processing. An existing backup is preserved
    and the PDF is replaced directly.

.PARAMETER RedoOcr
    Reprocesses existing OCR text and OCRs text in images using OCRmyPDF's
    `--redo-ocr` mode. It preserves visible text and vector graphics instead of
    rasterizing the entire page. OCRmyPDF optimization and optional Ghostscript
    processing remain enabled.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.EXAMPLE
    .\Invoke-PdfOptimization.ps1
    Starts interactively with the default language sequence, JPEG quality 75,
    and automatic deskewing. The original is saved as an _orig file on success.

.EXAMPLE
    .\Invoke-PdfOptimization.ps1 -InputPath 'C:\PDFs' -RotatePages -GhostscriptDpi 150
    Processes all PDFs in C:\PDFs; Ghostscript downsamples images to 150 DPI and
    compresses them as JPEG. Originals are preserved as _orig files and rotated
    page correction is enabled.

.EXAMPLE
    .\Invoke-PdfOptimization.ps1 -InputPath 'C:\PDFs' -ReplaceOriginal
    Processes all PDFs in C:\PDFs and replaces the originals without backups.

.EXAMPLE
    .\Invoke-PdfOptimization.ps1 -InputPath 'C:\PDFs' -RedoOcr
    Reprocesses existing OCR text and scans image content for text.

.NOTES
    Dependencies:
      - Python
      - OCRmyPDF (Python module)
      - pikepdf (used for signature checking and installed with OCRmyPDF)
      - Tesseract
      - Ghostscript (required only with -GhostscriptDpi > 0)

    Use .\Setup-PdfProcessor.ps1 to check and install the required software.

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

    # Automatically correct pages rotated by 90°, 180°, or 270° (disabled by default).
    [switch] $RotatePages,

    # Disable the optional Ghostscript post-processing stage (disabled by default).
    [switch] $NoGhostscript,

    # Replace input without a backup (an _orig backup is created by default).
    [switch] $ReplaceOriginal,

    # Reprocess existing OCR text without rasterizing visible page content.
    [switch] $RedoOcr,

    # Force English console output regardless of the Windows display language.
    [switch] $EnglishOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'internal\Get-PdfPythonRuntime.ps1')

$script:OutputLanguage = if (
    $EnglishOutput -or [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'de'
) { 'en' } else { 'de' }
$script:GermanMessages = if ($script:OutputLanguage -eq 'de') {
    Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1')
}
else { @{} }

<#
.SYNOPSIS
    Returns a localized console message.

.DESCRIPTION
    Uses the German message catalog when German output is selected; otherwise
    returns the English source string. Formats the selected template when
    formatting arguments are provided.

.PARAMETER Text
    English source message and lookup key.

.PARAMETER Arguments
    Optional values used to format placeholders in the message.

.OUTPUTS
    System.String. The localized and optionally formatted message.
#>
function Get-LocalizedText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [AllowEmptyCollection()][object[]] $Arguments = @()
    )

    $template = if ($script:OutputLanguage -eq 'de' -and $script:GermanMessages.ContainsKey($Text)) {
        $script:GermanMessages[$Text]
    }
    else { $Text }
    if ($Arguments.Count -gt 0) { return $template -f $Arguments }
    return $template
}

# Default OCR language sequence: German, English, French, Italian, and Spanish.
$script:DefaultLanguage = 'deu+eng+fra+ita+spa'

# Required languages: processing stops with a notice if deu or eng is missing.
$script:RequiredLanguages = @('deu', 'eng')

# Source for Tesseract language data (.traineddata), which users must download
# and place in the local tessdata folder.
$script:TessdataUrl = 'https://github.com/tesseract-ocr/tessdata_best'

# --- Helper functions ------------------------------------------------------

<#
.SYNOPSIS
    Formats an argument for ProcessStartInfo.Arguments.

.DESCRIPTION
    Encloses an argument in quotation marks and escapes embedded quotation
    marks and trailing backslashes for Windows PowerShell 5.1.

.PARAMETER Value
    Argument text to pass as a single process argument.

.OUTPUTS
    System.String. The correctly quoted argument.
#>
function ConvertTo-QuotedArgument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Value)

    # Double each backslash immediately before a quotation mark.
    $escaped = [regex]::Replace($Value, '(\\)(?=")', '$1$1')
    # Double any remaining trailing backslashes.
    if ($escaped.EndsWith('\')) { $escaped = $escaped + '\' }
    # Escape embedded quotation marks.
    $escaped = $escaped -replace '"', '\"'
    return '"' + $escaped + '"'
}

function Get-ExecutablePath {
<#
.SYNOPSIS
    Gets the path to a program.

.DESCRIPTION
    Searches the current PATH and returns the path of the first matching command.

.PARAMETER Name
    Name of the executable command.

.OUTPUTS
    System.String, or $null if the command was not found.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) { return $null }
    return $command.Source
}

function Test-PythonModule {
<#
.SYNOPSIS
    Tests whether a Python module can be imported.

.DESCRIPTION
    Starts Python directly with redirected streams and checks the import exit code.

.PARAMETER PythonPath
    Path to the Python installation.

.PARAMETER ModuleName
    Name of the Python module to import.

.OUTPUTS
    System.Boolean. $true if the module was imported successfully.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string] $ModuleName
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $PythonPath
    $startInfo.Arguments = "-c `"import $ModuleName`""
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { return $false }
        # Read both streams asynchronously to prevent pipe deadlocks.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdoutTask.GetAwaiter().GetResult() | Out-Null
        $stderrTask.GetAwaiter().GetResult() | Out-Null
        return ($process.ExitCode -eq 0)
    }
    catch { return $false }
    finally { $process.Dispose() }
}

function Get-MissingDependency {
<#
.SYNOPSIS
    Checks required and optional dependencies.

.DESCRIPTION
    Gets the selected Python interpreter, checks each required Python module,
    and resolves other executables. Missing Ghostscript is reported as an
    optional dependency and does not block processing.

.PARAMETER NoGhostscript
    Skips the Ghostscript lookup.

.OUTPUTS
    PSCustomObject with PythonPath, GhostscriptPath, Missing, and OptionalMissing.
#>
    [CmdletBinding()]
    param([bool] $NoGhostscript = $false)

    $missing = [System.Collections.Generic.List[string]]::new()
    $optionalMissing = [System.Collections.Generic.List[string]]::new()
    $pythonRuntime = Get-PdfPythonRuntime
    $pythonPath = if ($pythonRuntime) { $pythonRuntime.Path } else { $null }
    if (-not $pythonPath) { $missing.Add((Get-LocalizedText 'Python interpreter')) }
    if (-not (Get-ExecutablePath -Name 'tesseract')) { $missing.Add('Tesseract') }

    # Ghostscript is the optional optimization stage after OCRmyPDF.
    $ghostscriptPath = $null
    if (-not $NoGhostscript) {
        $ghostscriptPath = Get-ExecutablePath -Name 'gswin64c'
        if (-not $ghostscriptPath) { $ghostscriptPath = Get-ExecutablePath -Name 'gswin32c' }
        if (-not $ghostscriptPath) { $ghostscriptPath = Get-ExecutablePath -Name 'gs' }
        if (-not $ghostscriptPath) { $optionalMissing.Add((Get-LocalizedText 'Ghostscript (required only with -GhostscriptDpi)')) }
    }

    # pngquant is optional for OCRmyPDF optimization and must not block the run.
    # jbig2 is intentionally not used; it is relevant only for monochrome images.
    if ($pythonPath -and -not (Test-PythonModule -PythonPath $pythonPath -ModuleName 'ocrmypdf')) {
        $missing.Add((Get-LocalizedText 'OCRmyPDF (Python module)'))
    }
    if ($pythonPath -and -not (Test-PythonModule -PythonPath $pythonPath -ModuleName 'pikepdf')) {
        $missing.Add((Get-LocalizedText 'pikepdf (Python module)'))
    }

    [pscustomobject]@{
        PythonPath      = $pythonPath
        PythonScope     = if ($pythonRuntime) { $pythonRuntime.Scope } else { $null }
        GhostscriptPath = $ghostscriptPath
        Missing         = $missing
        OptionalMissing = $optionalMissing
    }
}

function Invoke-Tesseract {
<#
.SYNOPSIS
    Runs Tesseract with the specified arguments.

.DESCRIPTION
    Starts Tesseract directly and reads redirected output streams asynchronously
    so errors can be evaluated reliably and the pipes do not block.

.PARAMETER TesseractPath
    Path to the Tesseract executable.

.PARAMETER Arguments
    Argument string for Tesseract.

.OUTPUTS
    PSCustomObject with ExitCode, StdOut, and StdErr.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $TesseractPath,
        [Parameter(Mandatory)][string] $Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $TesseractPath
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw (Get-LocalizedText 'Tesseract could not be started.') }
        # Read asynchronously so large output cannot block the pipe.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdoutTask.GetAwaiter().GetResult()
            StdErr   = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally { $process.Dispose() }
}

function Get-TesseractLanguages {
<#
.SYNOPSIS
    Gets installed Tesseract languages and the tessdata folder.

.DESCRIPTION
    Runs `tesseract --list-langs` and reads available language codes and the
    tessdata path from its output.

.PARAMETER TesseractPath
    Path to the Tesseract executable.

.OUTPUTS
    PSCustomObject with Languages and TessdataPath.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $TesseractPath)

    $result = Invoke-Tesseract -TesseractPath $TesseractPath -Arguments '--list-langs'
    if ($result.ExitCode -ne 0) {
        throw (Get-LocalizedText -Text 'Tesseract --list-langs failed: {0}' -Arguments @($result.StdErr))
    }

    # The header names the tessdata folder in quotation marks, for example:
    # List of available languages in "C:\Program Files\Tesseract-OCR\tessdata" (5):
    $tessdataPath = $null
    if ($result.StdOut -match 'List of available languages in "([^"]+)"') {
        $tessdataPath = $Matches[1]
    }
    if (-not $tessdataPath) {
        # Fallback: tessdata is typically located next to tesseract.exe.
        $tessdataPath = Join-Path -Path (Split-Path -Parent $TesseractPath) -ChildPath 'tessdata'
    }

    # Discard the header and retain only language codes.
    $languages = @($result.StdOut -split '\r?\n' | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and $_ -notmatch '^List of available languages' })

    [pscustomobject]@{ Languages = $languages; TessdataPath = $tessdataPath }
}

function Show-LanguageDownloadHint {
<#
.SYNOPSIS
    Displays a notice about missing Tesseract language data.

.DESCRIPTION
    Lists missing required languages, the download source, and the local
    tessdata folder where the language files must be placed.

.PARAMETER MissingLanguages
    Codes of the missing required languages.

.PARAMETER TessdataPath
    Local folder for Tesseract language files.

.OUTPUTS
    No pipeline output. Displays the notice with Write-Host.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $MissingLanguages,
        [Parameter(Mandatory)][string] $TessdataPath
    )

    Write-Host ''
    Write-Host (Get-LocalizedText -Text 'Missing required language data: {0}.' -Arguments @(($MissingLanguages -join ', ')))
    Write-Host (Get-LocalizedText -Text 'Download the required .traineddata files from {0}' -Arguments @($script:TessdataUrl))
    Write-Host (Get-LocalizedText -Text 'and place them in the local tessdata folder: {0}' -Arguments @($TessdataPath))
}

function Get-PdfInputFile {
<#
.SYNOPSIS
    Gets input PDF files from a path.

.DESCRIPTION
    Accepts a single PDF or PDFs from a folder. Folders are searched
    recursively, excluding _orig backups. If no path is provided, it is
    requested interactively.

.PARAMETER Path
    Optional path to a PDF file or folder.

.OUTPUTS
    System.IO.FileInfo[]. The PDF files to process.
#>
    [CmdletBinding()]
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Host ''
        Write-Host (Get-LocalizedText 'Available parameters:') -ForegroundColor Cyan
        Write-Host (Get-LocalizedText '  -InputPath <path>       PDF file or folder; prompts if omitted.')
        Write-Host (Get-LocalizedText '  -Language <languages>  OCR languages, e.g. deu+eng (default: deu+eng+fra+ita+spa).')
        Write-Host (Get-LocalizedText '  -JpegQuality <1-100>   JPEG quality (default: 75).')
        Write-Host (Get-LocalizedText '  -GhostscriptDpi <DPI>  Optional Ghostscript resolution (default: disabled).')
        Write-Host (Get-LocalizedText '  -NoDeskew              Disable deskewing (enabled by default).')
        Write-Host (Get-LocalizedText '  -RotatePages           Automatically correct rotated pages (default: off).')
        Write-Host (Get-LocalizedText '  -NoGhostscript         Disable Ghostscript compression (allowed by default).')
        Write-Host (Get-LocalizedText '  -ReplaceOriginal       Replace original without an _orig backup.')
        Write-Host (Get-LocalizedText '  -RedoOcr               Reprocess existing OCR text without rasterizing the whole page.')
        Write-Host (Get-LocalizedText '  -EnglishOutput         Force English console output.')
        Write-Host (Get-LocalizedText 'Press Ctrl+C to cancel input.') -ForegroundColor Yellow
        $Path = Read-Host -Prompt (Get-LocalizedText 'Path to a PDF file or a folder containing PDFs')
    }
    if ([string]::IsNullOrWhiteSpace($Path)) { throw (Get-LocalizedText 'No path was entered.') }
    $Path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (-not (Test-Path -LiteralPath $Path)) {
        throw (Get-LocalizedText -Text 'Path not found: {0}' -Arguments @($Path))
    }
    $item = Get-Item -LiteralPath $Path
    $script:InputDirectoryPath = if ($item.PSIsContainer) {
        $item.FullName
    }
    else {
        $item.DirectoryName
    }
    if ($item.PSIsContainer) {
        # Do not process _orig backups again during recursive discovery.
        return @(Get-ChildItem -LiteralPath $item.FullName -File -Filter '*.pdf' -Recurse |
            Where-Object { $_.BaseName -notmatch '_orig$' })
    }
    if ($item.Extension -ine '.pdf') { throw (Get-LocalizedText 'The selected file does not have a .pdf extension.') }
    return @($item)
}

function Get-FileSha256 {
<#
.SYNOPSIS
    Calculates a file's SHA-256 hash.

.DESCRIPTION
    Reads the file and returns its hash as a hexadecimal string.

.PARAMETER Path
    Path to the file to check.

.OUTPUTS
    System.String. SHA-256 hash in hexadecimal format.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $hashBytes = $sha256.ComputeHash($stream)
            return [System.BitConverter]::ToString($hashBytes).Replace('-', '')
        }
        finally { $stream.Dispose() }
    }
    finally { $sha256.Dispose() }
}

<#
.SYNOPSIS
    Optimizes a PDF file with Ghostscript.

.DESCRIPTION
    Downsamples images at the specified resolution and JPEG quality. Replaces
    the input file only if the result is smaller.

.PARAMETER GhostscriptPath
    Path to the Ghostscript executable.

.PARAMETER Pdf
    PDF file to optimize.

.PARAMETER Dpi
    Target resolution for downsampling.

.OUTPUTS
    System.Boolean. $true if the file was successfully reduced in size.
#>
function Optimize-WithGhostscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $GhostscriptPath,
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][int] $Dpi
    )

    $tempPath = Join-Path $Pdf.DirectoryName ('.{0}.gs.pdf.part' -f [guid]::NewGuid().ToString('N'))
    try {
        # Explicit downsampling parameters guarantee the target resolution for
        # color, grayscale, and monochrome images, embedded as JPEG.
        # -dCompatibilityLevel=1.5 sets the output PDF version to 1.5.
        $gsArgList = @(
            '-dBATCH', '-dNOPAUSE', '-dQUIET',
            '-sDEVICE=pdfwrite',
            '-dDownsampleColorImages=true',
            '-dDownsampleGrayImages=true',
            '-dDownsampleMonoImages=true',
            "-dColorImageResolution=$Dpi",
            "-dGrayImageResolution=$Dpi",
            "-dMonoImageResolution=$Dpi",
            '-dColorImageFilter=/DCTEncode',
            '-dGrayImageFilter=/DCTEncode',
            '-dAutoFilterColorImages=false',
            '-dAutoFilterGrayImages=false',
            '-dColorConversionStrategy=/sRGB',
            '-dColorConversionStrategyForImages=/sRGB',
            '-dJPEGQ=75',
            '-dCompatibilityLevel=1.5',
            ('-sOutputFile={0}' -f $tempPath),
            $Pdf.FullName
        )
        $argsString = ($gsArgList | ForEach-Object { ConvertTo-QuotedArgument -Value $_ }) -join ' '
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $GhostscriptPath
        $startInfo.Arguments = $argsString
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        try {
            if (-not $process.Start()) { return $false }
            # Read streams asynchronously to prevent pipe deadlocks.
            $process.StandardOutput.ReadToEndAsync() | Out-Null
            $process.StandardError.ReadToEndAsync() | Out-Null
            $process.WaitForExit()
            if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $tempPath)) { return $false }
        }
        finally { $process.Dispose() }
        $originalSize = $Pdf.Length
        $optimizedSize = (Get-Item -LiteralPath $tempPath).Length
        if ($optimizedSize -ge $originalSize) { return $false }
        Remove-Item -LiteralPath $Pdf.FullName -Force
        Move-Item -LiteralPath $tempPath -Destination $Pdf.FullName -Force
        return $true
    }
    catch { return $false }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- Main processing ------------------------------------------------------

function Invoke-PdfProcessing {
<#
.SYNOPSIS
    Processes and optimizes a single PDF file.

.DESCRIPTION
    Checks signatures and the text layer, runs OCRmyPDF, and optionally applies
    Ghostscript optimization. Encrypted and digitally signed PDFs are skipped.
    The result replaces the input; by default, the original is first saved as
    _orig.pdf. OCR is skipped for PDFs with a full text layer, but PDF
    optimization remains active. --optimize 1 avoids the optional jbig2
    dependency.

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

.PARAMETER RotatePages
    Enables detection and correction of rotated pages.

.PARAMETER NoGhostscript
    Disables Ghostscript.

.PARAMETER ReplaceOriginal
    Replaces the input without creating an _orig backup.

.PARAMETER RedoOcr
    Reprocesses existing OCR text with OCRmyPDF's `--redo-ocr` mode.

.PARAMETER GhostscriptPath
    Path to Ghostscript, if available.

.OUTPUTS
    PSCustomObject with success and skip status, file path, failure reason,
    warning, and size values.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string] $Language,
        [Parameter(Mandatory)][int] $Quality,
        [Parameter(Mandatory)][int] $GhostscriptDpi,
        [Parameter(Mandatory)][bool] $NoDeskew,
        [Parameter(Mandatory)][bool] $RotatePages,
        [Parameter(Mandatory)][bool] $NoGhostscript,
        [Parameter(Mandatory)][bool] $ReplaceOriginal,
        [Parameter(Mandatory)][bool] $RedoOcr,
        [string] $GhostscriptPath
    )

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
        Write-Host (Get-LocalizedText -Text 'Processing: {0}' -Arguments @($Pdf.Name))
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

def stream_has_text(stream, resources, visited):
    key = object_key(stream)
    if key in visited:
        return False
    visited.add(key)
    xobjects = resources.get("/XObject", {})
    for operands, operator in pikepdf.parse_content_stream(stream):
        if str(operator) in TEXT_OPERATORS:
            return True
        if str(operator) == "Do" and operands:
            child = xobjects.get(operands[0])
            if child is not None and str(child.get("/Subtype")) == "/Form":
                child_resources = child.get("/Resources", resources)
                if stream_has_text(child, child_resources, visited):
                    return True
    return False

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
    text_pages = sum(
        stream_has_text(page, inherited_resources(page.obj), set())
        for page in pdf.pages
    )
    print(f"{'SIGNED' if signed else 'UNSIGNED'}\t{len(pdf.pages)}\t{text_pages}")
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
            throw (Get-LocalizedText -Text 'Signature and text-layer check failed (exit code {0}): {1}' -Arguments @($signatureCheckExitCode, $checkDetails))
        }
        $signatureStatus = ($signatureCheckOutput | ForEach-Object { $_.ToString() }) -join ''
        if ($signatureStatus.Trim() -eq 'ENCRYPTED') {
            $failureReason = Get-LocalizedText 'Encrypted (password required)'
            Write-Warning (Get-LocalizedText -Text "Skipped: '{0}'`nThe PDF is encrypted and cannot be processed without a password." -Arguments @($Pdf.Name))
            return [pscustomobject]@{ Success = $false; Skipped = $true; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $null; OriginalBytes = [long]0; ResultBytes = [long]0 }
        }
        $signatureValues = $signatureStatus.Trim() -split "`t"
        if (
            $signatureValues.Count -ne 3 -or
            $signatureValues[0] -notin @('SIGNED', 'UNSIGNED') -or
            $signatureValues[1] -notmatch '^\d+$' -or
            $signatureValues[2] -notmatch '^\d+$'
        ) {
            throw (Get-LocalizedText -Text "Signature and text-layer check returned an invalid result: '{0}'" -Arguments @($signatureStatus))
        }
        $signatureStatus = $signatureValues[0]
        $pageCount = [int]$signatureValues[1]
        $textPageCount = [int]$signatureValues[2]
        if ($pageCount -eq 0) {
            throw (Get-LocalizedText 'The PDF file contains no pages.')
        }
        $hasFullTextLayer = $textPageCount -eq $pageCount
        if ($signatureStatus -eq 'SIGNED') {
            $failureReason = Get-LocalizedText 'Digitally signed PDF'
            $failureDetails = Get-LocalizedText 'The input PDF has a digital signature. OCR would alter the document and invalidate the signature.'
            Write-Warning (Get-LocalizedText -Text "Skipped: '{0}'`n{1}" -Arguments @($Pdf.Name, $failureDetails))
            return [pscustomobject]@{ Success = $false; Skipped = $true; FilePath = $Pdf.FullName; FailureReason = $failureReason; Warning = $null; OriginalBytes = [long]0; ResultBytes = [long]0 }
        }

        if (-not $ReplaceOriginal -and (Test-Path -LiteralPath $originalPath)) {
            $relativeOriginalPath = $originalPath.Substring($Pdf.DirectoryName.Length + 1)
            $backupWarning = Get-LocalizedText 'Backup already exists'
            Write-Warning (Get-LocalizedText -Text "Backup '{0}' already exists and will be preserved; replacing the PDF directly." -Arguments @($relativeOriginalPath))
        }

        if ($hasFullTextLayer -and -not $RedoOcr) {
            Write-Host (Get-LocalizedText -Text 'A full text layer was found on all {0} pages; OCRmyPDF will skip OCR and continue with PDF optimization.' -Arguments @($pageCount)) -ForegroundColor Green
        }

        $ocrArguments = @(
            '-m', 'ocrmypdf',
            '--output-type', 'pdf',
            '--optimize', '1',
            '--jpeg-quality', "$Quality",
            '--language', $Language
        )
        if ($RedoOcr) {
            $ocrArguments += '--redo-ocr'
        }
        else {
            $ocrArguments += '--skip-text'
        }
        if (-not $NoDeskew) { $ocrArguments += '--deskew' }
        if ($RotatePages) { $ocrArguments += @('--rotate-pages', '--rotate-pages-threshold', '5') }
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
            $failureReason = Get-LocalizedText -Text 'OCRmyPDF error (exit code {0})' -Arguments @($ocrExitCode)
            $failureDetails = Get-LocalizedText -Text '{0}. See the OCRmyPDF console output for details.' -Arguments @($failureReason)
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
            Write-Host (Get-LocalizedText 'The result is identical to the original (no changes); discarding the output.') -ForegroundColor Yellow
            return [pscustomobject]@{ Success = $false; Skipped = $false; FilePath = $Pdf.FullName; FailureReason = (Get-LocalizedText 'No changes'); Warning = $backupWarning; OriginalBytes = [long]$originalSize; ResultBytes = [long]0 }
        }

        # Replace the input only after successful processing and hash validation.
        if (-not $ReplaceOriginal -and -not (Test-Path -LiteralPath $originalPath)) {
            [System.IO.File]::Replace($tempPath, $Pdf.FullName, $originalPath)
            Write-Host (Get-LocalizedText -Text 'Original backed up: {0}' -Arguments @($originalPath))
        }
        else {
            [System.IO.File]::Replace($tempPath, $Pdf.FullName, $replaceBackupPath)
        }
        if ($resultSize -lt $originalSize) {
            Write-Host (Get-LocalizedText -Text 'Optimized: {0:N1} MB -> {1:N1} MB' -Arguments @(($originalSize / 1MB), ($resultSize / 1MB))) -ForegroundColor Green
        }
        else {
            Write-Host (Get-LocalizedText -Text 'Processed (larger than original): {0:N1} MB -> {1:N1} MB' -Arguments @(($originalSize / 1MB), ($resultSize / 1MB))) -ForegroundColor Cyan
        }
        Write-Host (Get-LocalizedText -Text 'Saved: {0}' -Arguments @($Pdf.FullName))
        return [pscustomobject]@{ Success = $true; Skipped = $false; FilePath = $Pdf.FullName; FailureReason = $null; Warning = $backupWarning; OriginalBytes = [long]$originalSize; ResultBytes = [long]$resultSize }
    }
    catch {
        if (-not $failureDetails) { $failureDetails = $_.Exception.Message }
        Write-Warning (Get-LocalizedText -Text "Error processing '{0}':`n{1}" -Arguments @($Pdf.Name, $failureDetails))
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
$dependencyCheck = Get-MissingDependency -NoGhostscript $NoGhostscript.IsPresent
if ($dependencyCheck.Missing.Count -gt 0) {
    Write-Host "`n$(Get-LocalizedText 'Missing dependencies:')" -ForegroundColor Yellow
    $dependencyCheck.Missing | ForEach-Object { Write-Host "  - $_" }
    Write-Host "`n$(Get-LocalizedText 'Run Setup-PdfProcessor.ps1 to install the missing dependencies.')"
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
    $tesseractInfo = Get-TesseractLanguages -TesseractPath $tesseractPath
}
catch {
    Write-Error (Get-LocalizedText -Text 'Could not get Tesseract languages. Check "tesseract --list-langs": {0}' -Arguments @($_.Exception.Message))
    exit 1
}
$installedLanguages = @($tesseractInfo.Languages)

# --- Discover input files --------------------------------------------------
try { $pdfFiles = @(Get-PdfInputFile -Path $InputPath) }
catch { Write-Error $_.Exception.Message; exit 1 }
if ($pdfFiles.Count -eq 0) { Write-Host (Get-LocalizedText 'No PDFs found.'); exit 0 }
$summaryPathSegments = @($script:InputDirectoryPath.TrimEnd('\') -split '[\\/]' | Where-Object { $_ })
$summaryPathTail = @($summaryPathSegments | Select-Object -Last 3)
$summaryPath = '.\' + ($summaryPathTail -join '\') + '\'
$basePathPrefix = $script:InputDirectoryPath
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
    Show-LanguageDownloadHint -MissingLanguages $missingRequired -TessdataPath $tesseractInfo.TessdataPath
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
Write-Host (Get-LocalizedText 'Output format: standard PDF (version 1.5)')

# --- Process PDFs ---------------------------------------------------------
$results = @()
for ($i = 0; $i -lt $pdfFiles.Count; $i++) {
    $pdf = $pdfFiles[$i]
    Write-Host ''
    Write-Host (Get-LocalizedText -Text '--- File {0}/{1}: {2} ---' -Arguments @(($i + 1), $pdfFiles.Count, $pdf.Name)) -ForegroundColor Cyan
    $r = Invoke-PdfProcessing -Pdf $pdf -PythonPath $dependencyCheck.PythonPath `
        -Language $languageSelection -Quality $JpegQuality -GhostscriptDpi $GhostscriptDpi `
        -NoDeskew $NoDeskew.IsPresent -RotatePages $RotatePages.IsPresent `
        -NoGhostscript $NoGhostscript.IsPresent -ReplaceOriginal $ReplaceOriginal.IsPresent `
        -RedoOcr $RedoOcr.IsPresent `
        -GhostscriptPath $dependencyCheck.GhostscriptPath
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
