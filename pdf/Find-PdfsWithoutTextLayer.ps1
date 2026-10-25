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
    Use .\Setup-PdfProcessor.ps1 to install missing dependencies into the
    selected Python interpreter.
    No files are modified, and administrator rights are not required.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors

[CmdletBinding()]
param(
    [string] $InputPath,

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

<#
.SYNOPSIS
    Formats an argument for ProcessStartInfo.Arguments.

.DESCRIPTION
    Escapes quotation marks and backslashes so the argument is passed as a
    single process argument under Windows PowerShell 5.1.

.PARAMETER Value
    Argument text to quote.

.OUTPUTS
    System.String. The correctly quoted argument.
#>
function ConvertTo-QuotedArgument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Value)

    $escaped = [regex]::Replace($Value, '(\\)(?=")', '$1$1')
    if ($escaped.EndsWith('\')) { $escaped += '\' }
    $escaped = $escaped -replace '"', '\"'
    return '"' + $escaped + '"'
}

<#
.SYNOPSIS
    Runs Python with the specified arguments.

.DESCRIPTION
    Starts Python directly, reads standard output and error asynchronously, and
    returns both streams with the exit code.

.PARAMETER PythonPath
    Path to the Python installation.

.PARAMETER Arguments
    Argument list for the Python process.

.OUTPUTS
    PSCustomObject with ExitCode, StdOut, and StdErr.
#>
function Invoke-PythonCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string[]] $Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $PythonPath
    $startInfo.Arguments = ($Arguments | ForEach-Object { ConvertTo-QuotedArgument -Value $_ }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw (Get-LocalizedText -Text 'Python could not be started: {0}' -Arguments @($PythonPath))
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdoutTask.GetAwaiter().GetResult()
            StdErr   = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

<#
.SYNOPSIS
    Gets the PDF text-layer status.

.DESCRIPTION
    Checks page content, including embedded Form XObjects, for text operators
    and classifies the PDF based on the proportion of pages containing text.

.PARAMETER Pdf
    PDF file whose text layer is being checked.

.PARAMETER PythonPath
    Path to the Python installation with pikepdf.

.OUTPUTS
    PSCustomObject with FilePath, PageCount, TextPageCount, Status, and Error.
#>
function Get-PdfTextLayerStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][string] $PythonPath
    )

    $pythonCode = @'
import sys
import pikepdf

TEXT_OPERATORS = {"Tj", "TJ", "'", '"'}

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
    with pikepdf.open(sys.argv[1]) as pdf:
        text_pages = 0
        for page in pdf.pages:
            resources = inherited_resources(page.obj)
            if stream_has_text(page, resources, set()):
                text_pages += 1
        print(f"{len(pdf.pages)}\t{text_pages}")
except Exception as error:
    message = str(error)
    input_path = sys.argv[1]
    if message.lower().startswith(input_path.lower()):
        message = message[len(input_path):].lstrip(": ")
    print(f"{type(error).__name__}: {message}", file=sys.stderr)
    sys.exit(1)
'@

    $result = Invoke-PythonCommand -PythonPath $PythonPath -Arguments @('-c', $pythonCode, $Pdf.FullName)
    if ($result.ExitCode -ne 0) {
        $details = $result.StdErr.Trim()
        if (-not $details) { $details = $result.StdOut.Trim() }
        throw (Get-LocalizedText -Text 'PDF check failed (exit code {0}): {1}' -Arguments @($result.ExitCode, $details))
    }

    $values = $result.StdOut.Trim() -split "`t"
    if ($values.Count -ne 2 -or $values[0] -notmatch '^\d+$' -or $values[1] -notmatch '^\d+$') {
        throw (Get-LocalizedText -Text 'Python returned an invalid check result for ''{0}''.' -Arguments @($Pdf.FullName))
    }

    $pageCount = [int]$values[0]
    $textPageCount = [int]$values[1]
    if ($pageCount -eq 0) {
        throw (Get-LocalizedText 'The PDF file contains no pages.')
    }

    $status = if ($textPageCount -eq 0) {
        'NoTextLayer'
    }
    elseif ($textPageCount -lt $pageCount) {
        'PartialTextLayer'
    }
    else {
        'TextLayerPresent'
    }

    return [pscustomobject]@{
        FilePath      = $Pdf.FullName
        PageCount     = $pageCount
        TextPageCount = $textPageCount
        Status        = $status
        Error         = $null
    }
}

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
    Write-Host (Get-LocalizedText 'Run Setup-PdfProcessor.ps1 to install the missing dependencies.')
    exit 1
}
$pythonPath = $pythonRuntime.Path

$moduleCheck = Invoke-PythonCommand -PythonPath $pythonPath -Arguments @('-c', 'import pikepdf')
if ($moduleCheck.ExitCode -ne 0) {
    Write-Host (Get-LocalizedText 'Missing dependency: Python module pikepdf.') -ForegroundColor Yellow
    Write-Host (Get-LocalizedText 'Run Setup-PdfProcessor.ps1 to install the missing dependencies.')
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
            $result = Get-PdfTextLayerStatus -Pdf $pdf -PythonPath $pythonPath
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
