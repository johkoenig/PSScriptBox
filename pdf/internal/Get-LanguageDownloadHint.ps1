<#
.SYNOPSIS
    Provides the language download notice for the OCR script.

.DESCRIPTION
    Defines Get-LanguageDownloadHint, which builds the notice about missing
    Tesseract language data. The caller decides how to display it.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Uses Get-LocalizedText.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Builds the notice about missing Tesseract language data.

.DESCRIPTION
    Returns three lines: the missing required languages, the download source,
    and the local tessdata folder where the language files must be placed.

.PARAMETER MissingLanguages
    Codes of the missing required languages.

.PARAMETER TessdataPath
    Local folder for Tesseract language files.

.PARAMETER TessdataUrl
    Source URL for the .traineddata files.

.PARAMETER UiLanguage
    Language of the messages: 'de' selects the German catalog, anything else English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.OUTPUTS
    System.String[]. The notice lines in display order.
#>
function Get-LanguageDownloadHint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $MissingLanguages,
        [Parameter(Mandatory)][string] $TessdataPath,
        [Parameter(Mandatory)][string] $TessdataUrl,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{}
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }
    return @(
        (Get-LocalizedText @localization -Text 'Missing required language data: {0}.' -Arguments @(($MissingLanguages -join ', '))),
        (Get-LocalizedText @localization -Text 'Download the required .traineddata files from {0}' -Arguments @($TessdataUrl)),
        (Get-LocalizedText @localization -Text 'and place them in the local tessdata folder: {0}' -Arguments @($TessdataPath))
    )
}
