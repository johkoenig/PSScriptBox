<#
.SYNOPSIS
    Provides the PDF text-layer inspection helper for the PDF scripts.

.DESCRIPTION
    Defines Get-PdfTextLayerStatus, which runs a pikepdf inspection of one PDF
    and classifies it as having no, partial, or complete text coverage.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7, Python with the pikepdf
    module. Requires Invoke-PythonCommand and Get-LocalizedText to be dot-sourced
    by the caller.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Gets the PDF text-layer status.

.DESCRIPTION
    Checks page content, including embedded Form XObjects, for text operators
    and classifies the PDF based on the proportion of pages containing text.
    Returns NoTextLayer when no page has text, PartialTextLayer when only some
    pages have text, and TextLayerPresent when every page has text. Throws when
    Python fails, returns an invalid result, or the PDF has no pages.

.PARAMETER Pdf
    PDF file whose text layer is being checked.

.PARAMETER PythonPath
    Path to the Python installation with pikepdf.

.PARAMETER UiLanguage
    'de' selects German messages; any other value selects English.

.PARAMETER Messages
    German catalog keyed by the English source text.

.OUTPUTS
    PSCustomObject with FilePath, PageCount, TextPageCount, Status, and Error.
#>
function Get-PdfTextLayerStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][string] $PythonPath,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{}
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }

    # The inspection runs as an embedded script so that no helper file is needed beside the PDF.
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

    $result = Invoke-PythonCommand -PythonPath $PythonPath -Arguments @('-c', $pythonCode, $Pdf.FullName) `
        -UiLanguage $UiLanguage -Messages $Messages
    if ($result.ExitCode -ne 0) {
        $details = $result.StdErr.Trim()
        if (-not $details) { $details = $result.StdOut.Trim() }
        throw (Get-LocalizedText @localization -Text 'PDF check failed (exit code {0}): {1}' -Arguments @($result.ExitCode, $details))
    }

    $values = $result.StdOut.Trim() -split "`t"
    if ($values.Count -ne 2 -or $values[0] -notmatch '^\d+$' -or $values[1] -notmatch '^\d+$') {
        throw (Get-LocalizedText @localization -Text 'Python returned an invalid check result for ''{0}''.' -Arguments @($Pdf.FullName))
    }

    $pageCount = [int]$values[0]
    $textPageCount = [int]$values[1]
    if ($pageCount -eq 0) {
        throw (Get-LocalizedText @localization 'The PDF file contains no pages.')
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
