<#
.SYNOPSIS
    Provides the setup report builder for the PDF processor setup.

.DESCRIPTION
    Defines Get-PdfSetupStateReport, which turns a dependency state into
    localized report lines with optional console colors. The top-level script
    prints the lines.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Requires
    Get-ToolStatusLabel and Get-LocalizedText from the same internal folder.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Builds the localized dependency state report.

.DESCRIPTION
    Returns one object per console line in display order. Each object has a Text
    property and a Color property. Color is $null for uncoloured lines. The
    function writes nothing to the console.

.PARAMETER State
    Dependency state returned by Get-PdfSetupState.

.PARAMETER UiLanguage
    'de' selects German messages; any other value selects English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.OUTPUTS
    PSCustomObject[] with Text and Color properties.
#>
function Get-PdfSetupStateReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject] $State,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{}
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }
    $lines = [System.Collections.Generic.List[object]]::new()
    $addLine = {
        param([string] $Text, [string] $Color)
        $lines.Add([pscustomobject]@{ Text = $Text; Color = $Color })
    }

    $chocolateyStatus = Get-ToolStatusLabel -Available ([bool]$State.ChocolateyAvailable) -Path $State.ChocolateyPath -UiLanguage $UiLanguage -Messages $Messages
    $pythonStatus = Get-ToolStatusLabel -Available ([bool]$State.PythonAvailable) -Path $State.PythonPath -UiLanguage $UiLanguage -Messages $Messages
    $tesseractStatus = Get-ToolStatusLabel -Available ([bool]$State.TesseractAvailable) -Path $State.TesseractPath -UiLanguage $UiLanguage -Messages $Messages
    $ghostscriptStatus = Get-ToolStatusLabel -Available ([bool]$State.GhostscriptAvailable) -Path $State.GhostscriptPath -UiLanguage $UiLanguage -Messages $Messages

    & $addLine '' $null
    & $addLine (Get-LocalizedText @localization -Text 'Current dependency state:') 'Cyan'
    & $addLine (Get-LocalizedText @localization -Text 'Chocolatey:') 'DarkCyan'
    & $addLine (Get-LocalizedText @localization -Text '  {0}: {1}' -Arguments @('Chocolatey', $chocolateyStatus)) $null

    & $addLine (Get-LocalizedText @localization -Text 'Python:') 'DarkCyan'
    & $addLine (Get-LocalizedText @localization -Text '  {0}: {1}' -Arguments @('Python', $pythonStatus)) $null
    if ($State.PythonPath) {
        & $addLine (Get-LocalizedText @localization -Text '  Python executable: {0}' -Arguments @($State.PythonPath)) $null
        $scopeLabel = if ($State.PythonScope -eq 'User') {
            Get-LocalizedText @localization -Text 'Current user'
        }
        else {
            Get-LocalizedText @localization -Text 'Machine-wide'
        }
        & $addLine (Get-LocalizedText @localization -Text '  Python scope: {0}' -Arguments @($scopeLabel)) $null
    }
    $modules = @(
        @{ Name = 'OCRmyPDF'; Present = [bool]$State.OcrMyPdfAvailable }
        @{ Name = 'pikepdf'; Present = [bool]$State.PikePdfAvailable }
    )
    foreach ($module in $modules) {
        $status = if (-not $State.PythonAvailable) {
            Get-LocalizedText @localization -Text 'Not checked (Python is unavailable)'
        }
        elseif ($module.Present) {
            Get-LocalizedText @localization -Text 'Present'
        }
        else {
            Get-LocalizedText @localization -Text 'Missing'
        }
        & $addLine (Get-LocalizedText @localization -Text '  Python package {0}: {1}' -Arguments @($module.Name, $status)) $null
    }

    & $addLine (Get-LocalizedText @localization -Text 'Tesseract:') 'DarkCyan'
    & $addLine (Get-LocalizedText @localization -Text '  {0}: {1}' -Arguments @('Tesseract', $tesseractStatus)) $null
    & $addLine (Get-LocalizedText @localization -Text '  {0}: {1}' -Arguments @('Ghostscript', $ghostscriptStatus)) $null
    if ($State.TrainingStatus) {
        $trainingResult = if ($State.TrainingStatus.CheckSucceeded) {
            Get-LocalizedText @localization -Text 'Inspected'
        }
        else {
            Get-LocalizedText @localization -Text 'Could not inspect'
        }
        & $addLine (Get-LocalizedText @localization -Text '  Language data: {0}' -Arguments @($trainingResult)) $null
    }

    return $lines.ToArray()
}
