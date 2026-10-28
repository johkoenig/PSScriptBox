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
# Copyright (c) 2026 PSScriptBox contributors
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

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    PSCustomObject[] with Text and Color properties.
#>
function Get-PdfSetupStateReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject] $State,
        [string] $UiLanguage = 'en',
        [string]$MessagesPath = ''
    )
    $lines = [System.Collections.Generic.List[object]]::new()
    $addLine = {
        param([string] $Text, [string] $Color)
        $lines.Add([pscustomobject]@{ Text = $Text; Color = $Color })
    }

    $chocolateyStatus = Get-ToolStatusLabel -Available ([bool]$State.ChocolateyAvailable) -Path $State.ChocolateyPath -UiLanguage $UiLanguage -MessagesPath $MessagesPath
    $pythonStatus = Get-ToolStatusLabel -Available ([bool]$State.PythonAvailable) -Path $State.PythonPath -UiLanguage $UiLanguage -MessagesPath $MessagesPath
    $tesseractStatus = Get-ToolStatusLabel -Available ([bool]$State.TesseractAvailable) -Path $State.TesseractPath -UiLanguage $UiLanguage -MessagesPath $MessagesPath
    $ghostscriptStatus = Get-ToolStatusLabel -Available ([bool]$State.GhostscriptAvailable) -Path $State.GhostscriptPath -UiLanguage $UiLanguage -MessagesPath $MessagesPath

    & $addLine '' $null
    & $addLine (Get-LocalizedText -Text 'Current dependency state:' -Language $UiLanguage -MessagesPath $MessagesPath) 'Cyan'
    & $addLine (Get-LocalizedText -Text 'Chocolatey:' -Language $UiLanguage -MessagesPath $MessagesPath) 'DarkCyan'
    & $addLine (Get-LocalizedText -Text '  {0}: {1}' -Arguments @('Chocolatey', $chocolateyStatus) -Language $UiLanguage -MessagesPath $MessagesPath) $null

    & $addLine (Get-LocalizedText -Text 'Python:' -Language $UiLanguage -MessagesPath $MessagesPath) 'DarkCyan'
    & $addLine (Get-LocalizedText -Text '  {0}: {1}' -Arguments @('Python', $pythonStatus) -Language $UiLanguage -MessagesPath $MessagesPath) $null
    if ($State.PythonPath) {
        & $addLine (Get-LocalizedText -Text '  Python executable: {0}' -Arguments @($State.PythonPath) -Language $UiLanguage -MessagesPath $MessagesPath) $null
        $scopeLabel = if ($State.PythonScope -eq 'User') {
            Get-LocalizedText -Text 'Current user' -Language $UiLanguage -MessagesPath $MessagesPath
        }
        else {
            Get-LocalizedText -Text 'Machine-wide' -Language $UiLanguage -MessagesPath $MessagesPath
        }
        & $addLine (Get-LocalizedText -Text '  Python scope: {0}' -Arguments @($scopeLabel) -Language $UiLanguage -MessagesPath $MessagesPath) $null
    }
    $modules = @(
        @{ Name = 'OCRmyPDF'; Present = [bool]$State.OcrMyPdfAvailable }
        @{ Name = 'pikepdf'; Present = [bool]$State.PikePdfAvailable }
    )
    foreach ($module in $modules) {
        $status = if (-not $State.PythonAvailable) {
            Get-LocalizedText -Text 'Not checked (Python is unavailable)' -Language $UiLanguage -MessagesPath $MessagesPath
        }
        elseif ($module.Present) {
            Get-LocalizedText -Text 'Present' -Language $UiLanguage -MessagesPath $MessagesPath
        }
        else {
            Get-LocalizedText -Text 'Missing' -Language $UiLanguage -MessagesPath $MessagesPath
        }
        & $addLine (Get-LocalizedText -Text '  Python package {0}: {1}' -Arguments @($module.Name, $status) -Language $UiLanguage -MessagesPath $MessagesPath) $null
    }

    & $addLine (Get-LocalizedText -Text 'Tesseract:' -Language $UiLanguage -MessagesPath $MessagesPath) 'DarkCyan'
    & $addLine (Get-LocalizedText -Text '  {0}: {1}' -Arguments @('Tesseract', $tesseractStatus) -Language $UiLanguage -MessagesPath $MessagesPath) $null
    & $addLine (Get-LocalizedText -Text '  {0}: {1}' -Arguments @('Ghostscript', $ghostscriptStatus) -Language $UiLanguage -MessagesPath $MessagesPath) $null
    if ($State.TrainingStatus) {
        $trainingResult = if ($State.TrainingStatus.CheckSucceeded) {
            Get-LocalizedText -Text 'Inspected' -Language $UiLanguage -MessagesPath $MessagesPath
        }
        else {
            Get-LocalizedText -Text 'Could not inspect' -Language $UiLanguage -MessagesPath $MessagesPath
        }
        & $addLine (Get-LocalizedText -Text '  Language data: {0}' -Arguments @($trainingResult) -Language $UiLanguage -MessagesPath $MessagesPath) $null
    }

    return $lines.ToArray()
}
