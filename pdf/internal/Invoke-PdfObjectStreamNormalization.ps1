<#
.SYNOPSIS
    Provides the PDF object-stream normalization helper.

.DESCRIPTION
    Defines Invoke-PdfObjectStreamNormalization, which checks for object
    streams, rewrites only when they are present, and verifies that page and
    text-operator coverage remain unchanged.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7, Python, and pikepdf.
    Uses Invoke-PythonCommand and Get-LocalizedText.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Normalizes a PDF for broad parser compatibility.

.DESCRIPTION
    Uses pikepdf to check whether the PDF contains object streams and rewrites
    it with object streams disabled only when needed. Encrypted, signed, and
    PDFs without text-show operators are not rewritten. The saved result is
    reopened and checked to ensure object streams are absent and its page count
    and text-bearing page count match the input.

.PARAMETER PythonPath
    Path to the Python interpreter containing pikepdf.

.PARAMETER InputPath
    Path to the source PDF.

.PARAMETER OutputPath
    Path for a new output PDF. The file must not already exist.

.PARAMETER CheckOnly
    Checks whether normalization is needed without writing an output PDF.

.PARAMETER UiLanguage
    'de' selects German messages; any other value selects English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    PSCustomObject with Status, PageCount, TextPageCount, and OutputPath.
#>
function Invoke-PdfObjectStreamNormalization
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string] $InputPath,
        [Parameter(Mandatory)][string] $OutputPath,
        [switch] $CheckOnly,
        [string] $UiLanguage = 'en',
        [string] $MessagesPath = ''
    )

    $resolvedInputPath = [System.IO.Path]::GetFullPath($InputPath)
    $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    if ($resolvedInputPath -ieq $resolvedOutputPath)
    {
        throw 'The input and output PDF paths must be different.'
    }
    if (Test-Path -LiteralPath $resolvedOutputPath)
    {
        throw 'The output PDF path already exists.'
    }

    $pythonCode = @'
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
        operator_name = str(operator)
        if operator_name in TEXT_OPERATORS:
            return True
        if operator_name == "Do" and operands:
            child = xobjects.get(operands[0])
            if child is not None and str(child.get("/Subtype")) == "/Form":
                child_resources = child.get("/Resources", resources)
                if stream_has_text(child, child_resources, visited):
                    return True
    return False

def text_page_count(pdf):
    count = 0
    for page in pdf.pages:
        page_object = page.obj
        resources = inherited_resources(page_object)
        if stream_has_text(page_object, resources, set()):
            count += 1
    return count

def has_object_streams(pdf):
    return any(
        isinstance(obj, pikepdf.Stream) and str(obj.get("/Type")) == "/ObjStm"
        for obj in pdf.objects
    )

def signed_document(pdf):
    acro_form = pdf.Root.get("/AcroForm")
    fields = acro_form.get("/Fields", []) if acro_form is not None else []
    permissions = pdf.Root.get("/Perms")
    permission_signatures = (
        [permissions.get("/DocMDP"), permissions.get("/UR3")]
        if permissions is not None else []
    )
    return any(field_is_signed(field) for field in fields) or any(
        has_signature_value(value) for value in permission_signatures
    )

source_path, output_path, check_only = sys.argv[1:4]
check_only = check_only == "1"
try:
    try:
        pdf = pikepdf.open(source_path)
    except pikepdf.PasswordError:
        print("ENCRYPTED")
        sys.exit(0)

    with pdf:
        if pdf.is_encrypted:
            print("ENCRYPTED")
            sys.exit(0)
        page_count = len(pdf.pages)
        if page_count == 0:
            raise ValueError("The PDF file contains no pages.")
        pages_with_text = text_page_count(pdf)
        if signed_document(pdf):
            print(f"SIGNED\t{page_count}\t{pages_with_text}")
            sys.exit(0)
        if pages_with_text == 0:
            print(f"NO_TEXT_LAYER\t{page_count}\t0")
            sys.exit(0)
        if not has_object_streams(pdf):
            print(f"ALREADY_NORMALIZED\t{page_count}\t{pages_with_text}")
            sys.exit(0)
        if check_only:
            print(f"NEEDS_NORMALIZATION\t{page_count}\t{pages_with_text}")
            sys.exit(0)
        pdf.save(output_path, object_stream_mode=pikepdf.ObjectStreamMode.disable)

    with pikepdf.open(output_path) as normalized:
        normalized_pages = len(normalized.pages)
        normalized_text_pages = text_page_count(normalized)
        normalized_has_object_streams = has_object_streams(normalized)
    if normalized_has_object_streams:
        raise ValueError("The normalized PDF still contains object streams.")
    if normalized_pages != page_count or normalized_text_pages != pages_with_text:
        raise ValueError("The normalized PDF did not preserve its pages and text operators.")
    print(f"REPAIRED\t{normalized_pages}\t{normalized_text_pages}")
except Exception as error:
    print(f"{type(error).__name__}: {error}", file=sys.stderr)
    sys.exit(1)
'@

    $checkOnlyArgument = if ($CheckOnly)
    {
        '1'
    }
    else
    {
        '0'
    }
    $result = Invoke-PythonCommand -PythonPath $PythonPath `
        -Arguments @('-c', $pythonCode, $resolvedInputPath, $resolvedOutputPath, $checkOnlyArgument) `
        -UiLanguage $UiLanguage -MessagesPath $MessagesPath
    if ($result.ExitCode -ne 0)
    {
        $details = $result.StdErr.Trim()
        if (-not $details)
        {
            $details = $result.StdOut.Trim()
        }
        throw (Get-LocalizedText -Text 'PDF object-stream normalization failed (exit code {0}): {1}' `
                -Arguments @($result.ExitCode, $details) -Language $UiLanguage -MessagesPath $MessagesPath)
    }

    $values = $result.StdOut.Trim() -split "`t"
    if ($values[0] -eq 'ENCRYPTED')
    {
        return [pscustomobject]@{
            Status = 'Encrypted'
            PageCount = 0
            TextPageCount = 0
            OutputPath = $null
        }
    }
    if (
    $values.Count -lt 2 -or
            $values[1] -notmatch '^\d+$' -or
            [int]$values[1] -lt 1
    )
    {
        throw (Get-LocalizedText -Text 'Python returned an invalid object-stream result for ''{0}''.' `
                -Arguments @($resolvedInputPath) -Language $UiLanguage -MessagesPath $MessagesPath)
    }

    $pageCount = [int]$values[1]
    if ($values[0] -in @('SIGNED', 'NO_TEXT_LAYER', 'ALREADY_NORMALIZED', 'NEEDS_NORMALIZATION'))
    {
        if ($values.Count -ne 3 -or $values[2] -notmatch '^\d+$')
        {
            throw (Get-LocalizedText -Text 'Python returned an invalid object-stream result for ''{0}''.' `
                    -Arguments @($resolvedInputPath) -Language $UiLanguage -MessagesPath $MessagesPath)
        }
        $textPageCount = [int]$values[2]
        if (
        $textPageCount -gt $pageCount -or
                ($values[0] -eq 'NO_TEXT_LAYER' -and $textPageCount -ne 0) -or
                ($values[0] -eq 'ALREADY_NORMALIZED' -and $textPageCount -lt 1) -or
                ($values[0] -eq 'NEEDS_NORMALIZATION' -and (-not $CheckOnly -or $textPageCount -lt 1))
        )
        {
            throw (Get-LocalizedText -Text 'Python returned an invalid object-stream result for ''{0}''.' `
                    -Arguments @($resolvedInputPath) -Language $UiLanguage -MessagesPath $MessagesPath)
        }
        $status = switch ($values[0])
        {
            'SIGNED' {
                'Signed'
            }
            'NO_TEXT_LAYER' {
                'NoTextLayer'
            }
            'ALREADY_NORMALIZED' {
                'AlreadyNormalized'
            }
            'NEEDS_NORMALIZATION' {
                'NeedsNormalization'
            }
        }
        return [pscustomobject]@{
            Status = $status
            PageCount = $pageCount
            TextPageCount = $textPageCount
            OutputPath = $null
        }
    }
    if (
    $values[0] -ne 'REPAIRED' -or
            $values.Count -ne 3 -or
            $values[2] -notmatch '^\d+$' -or
            [int]$values[2] -lt 1 -or
            [int]$values[2] -gt $pageCount
    )
    {
        throw (Get-LocalizedText -Text 'Python returned an invalid object-stream result for ''{0}''.' `
                -Arguments @($resolvedInputPath) -Language $UiLanguage -MessagesPath $MessagesPath)
    }
    if (-not (Test-Path -LiteralPath $resolvedOutputPath -PathType Leaf))
    {
        throw (Get-LocalizedText 'The normalized PDF was not created.' -Language $UiLanguage -MessagesPath $MessagesPath)
    }
    if ((Get-Item -LiteralPath $resolvedOutputPath).Length -eq 0)
    {
        throw (Get-LocalizedText 'The normalized PDF was not created.' -Language $UiLanguage -MessagesPath $MessagesPath)
    }

    [pscustomobject]@{
        Status = 'Repaired'
        PageCount = $pageCount
        TextPageCount = [int]$values[2]
        OutputPath = $resolvedOutputPath
    }
}
