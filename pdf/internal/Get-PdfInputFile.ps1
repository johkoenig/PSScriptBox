<#
.SYNOPSIS
    Provides the input file discovery for the OCR script.

.DESCRIPTION
    Defines Get-PdfInputFile, which resolves a PDF file or a folder of PDFs into
    the list of files to process.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Uses Get-LocalizedText.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Gets input PDF files from a path.

.DESCRIPTION
    Accepts a single PDF or PDFs from a folder. Folders are searched
    recursively, excluding _orig backups. The function never prompts; the
    caller asks the user when no path is available.

.PARAMETER Path
    Path to a PDF file or folder. Surrounding quotation marks and environment
    variables are resolved.

.PARAMETER UiLanguage
    Language of error messages: 'de' selects the German catalog, anything else English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.OUTPUTS
    PSCustomObject with Files (System.IO.FileInfo[]) and BasePath (string). BasePath
    is the folder itself for a folder input and the parent folder for a file input.
#>
function Get-PdfInputFile {
    [CmdletBinding()]
    param(
        [string] $Path,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{}
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }
    if ([string]::IsNullOrWhiteSpace($Path)) { throw (Get-LocalizedText @localization -Text 'No path was entered.') }
    $Path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (-not (Test-Path -LiteralPath $Path)) {
        throw (Get-LocalizedText @localization -Text 'Path not found: {0}' -Arguments @($Path))
    }
    $item = Get-Item -LiteralPath $Path

    if ($item.PSIsContainer) {
        # Do not process _orig backups again during recursive discovery.
        $files = @(Get-ChildItem -LiteralPath $item.FullName -File -Filter '*.pdf' -Recurse |
            Where-Object { $_.BaseName -notmatch '_orig$' })
        $basePath = $item.FullName
    }
    else {
        if ($item.Extension -ine '.pdf') {
            throw (Get-LocalizedText @localization -Text 'The selected file does not have a .pdf extension.')
        }
        $files = @($item)
        $basePath = $item.DirectoryName
    }

    [pscustomobject]@{ Files = $files; BasePath = $basePath }
}
