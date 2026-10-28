<#
.SYNOPSIS
    Provides the Tesseract language lookup for the OCR script.

.DESCRIPTION
    Defines Get-TesseractLanguage, which reads the installed language codes and
    the tessdata folder from the output of tesseract --list-langs.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Uses Invoke-Tesseract.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Gets installed Tesseract languages and the tessdata folder.

.DESCRIPTION
    Runs `tesseract --list-langs` and reads available language codes and the
    tessdata path from its output. Writes nothing to the console.

.PARAMETER TesseractPath
    Path to the Tesseract executable.

.PARAMETER UiLanguage
    Language of error messages: 'de' selects the German catalog, anything else English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.OUTPUTS
    PSCustomObject with Languages (string array) and TessdataPath (string).
#>
function Get-TesseractLanguage
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $TesseractPath,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{}
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }
    $result = Invoke-Tesseract -TesseractPath $TesseractPath -Arguments '--list-langs' -UiLanguage $UiLanguage -Messages $Messages
    if ($result.ExitCode -ne 0) {
        throw (Get-LocalizedText @localization -Text 'Tesseract --list-langs failed: {0}' -Arguments @($result.StdErr))
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
