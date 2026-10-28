<#
.SYNOPSIS
    Provides the dependency state check for the PDF processor setup.

.DESCRIPTION
    Defines Get-PdfSetupState, which runs the version and import checks for the
    located tools and returns the resulting dependency state. It writes nothing
    to the console.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Requires
    Invoke-SetupProcess and Get-TesseractTrainingStatus from the same internal
    folder.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Collects the current PDF processor dependency state.

.DESCRIPTION
    Checks Chocolatey and Python executables, each Python package separately,
    Tesseract, Ghostscript, and installed Tesseract language data. Tool paths
    come from the ToolLocation object, so no lookups are repeated here. Checks
    only run for tools whose path was located.

.PARAMETER ToolLocation
    Object returned by Get-PdfToolLocation.

.PARAMETER UiLanguage
    'de' selects German messages; any other value selects English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    PSCustomObject containing executable paths and dependency status.
#>
function Get-PdfSetupState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject] $ToolLocation,
        [string] $UiLanguage = 'en',
        [string]$MessagesPath = ''
    )

    $processOptions = @{ UiLanguage = $UiLanguage; MessagesPath = $MessagesPath }

    $chocolateyPath = $ToolLocation.ChocolateyPath
    $chocolateyAvailable = $false
    if ($chocolateyPath) {
        $chocolateyCheck = Invoke-SetupProcess -FilePath $chocolateyPath -Arguments @('--version') @processOptions
        $chocolateyAvailable = $chocolateyCheck.ExitCode -eq 0
    }

    $pythonPath = $ToolLocation.PythonPath
    $pythonAvailable = $false
    if ($pythonPath) {
        $pythonCheck = Invoke-SetupProcess -FilePath $pythonPath -Arguments @('--version') @processOptions
        $pythonAvailable = $pythonCheck.ExitCode -eq 0
    }

    $ocrmypdfAvailable = $false
    $pikepdfAvailable = $false
    if ($pythonAvailable) {
        $ocrmypdfCheck = Invoke-SetupProcess -FilePath $pythonPath -Arguments @('-c', 'import ocrmypdf') @processOptions
        $pikepdfCheck = Invoke-SetupProcess -FilePath $pythonPath -Arguments @('-c', 'import pikepdf') @processOptions
        $ocrmypdfAvailable = $ocrmypdfCheck.ExitCode -eq 0
        $pikepdfAvailable = $pikepdfCheck.ExitCode -eq 0
    }

    $tesseractPath = $ToolLocation.TesseractPath
    $tesseractAvailable = $false
    if ($tesseractPath) {
        $tesseractCheck = Invoke-SetupProcess -FilePath $tesseractPath -Arguments @('--version') @processOptions
        $tesseractAvailable = $tesseractCheck.ExitCode -eq 0
    }

    $ghostscriptPath = $ToolLocation.GhostscriptPath
    $ghostscriptAvailable = $false
    if ($ghostscriptPath) {
        $ghostscriptCheck = Invoke-SetupProcess -FilePath $ghostscriptPath -Arguments @('-version') @processOptions
        $ghostscriptAvailable = $ghostscriptCheck.ExitCode -eq 0
    }

    $trainingStatus = $null
    if ($tesseractAvailable) {
        $trainingStatus = Get-TesseractTrainingStatus -TesseractPath $tesseractPath @processOptions
    }

    return [pscustomobject]@{
        ChocolateyPath       = $chocolateyPath
        ChocolateyAvailable  = $chocolateyAvailable
        PythonPath           = $pythonPath
        PythonAvailable      = $pythonAvailable
        PythonScope          = $ToolLocation.PythonScope
        OcrMyPdfAvailable    = $ocrmypdfAvailable
        PikePdfAvailable     = $pikepdfAvailable
        TesseractPath        = $tesseractPath
        TesseractAvailable   = $tesseractAvailable
        GhostscriptPath      = $ghostscriptPath
        GhostscriptAvailable = $ghostscriptAvailable
        TrainingStatus       = $trainingStatus
    }
}
