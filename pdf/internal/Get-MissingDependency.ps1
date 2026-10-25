<#
.SYNOPSIS
    Provides the dependency check for the OCR script.

.DESCRIPTION
    Defines Get-MissingDependency, which evaluates already resolved tool locations
    and reports missing required and optional dependencies.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Uses Test-PythonModule.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Checks required and optional dependencies.

.DESCRIPTION
    Checks the Python interpreter, the Tesseract executable, and the OCRmyPDF and
    pikepdf Python modules. Missing Ghostscript is reported as an optional
    dependency and does not block processing. The caller resolves the locations,
    so this function reads no environment state.

.PARAMETER PythonRuntime
    Python runtime object with Path and Scope properties, or $null if none was found.

.PARAMETER TesseractPath
    Resolved Tesseract executable path, or $null if missing.

.PARAMETER GhostscriptPath
    Resolved Ghostscript executable path, or $null if missing.

.PARAMETER NoGhostscript
    Ignores Ghostscript entirely; no optional warning is produced.

.PARAMETER UiLanguage
    Language of the messages: 'de' selects the German catalog, anything else English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.OUTPUTS
    PSCustomObject with PythonPath, PythonScope, GhostscriptPath, Missing (list of
    required items), and OptionalMissing (list of optional items).
#>
function Get-MissingDependency {
    [CmdletBinding()]
    param(
        [AllowNull()][object] $PythonRuntime,
        [AllowNull()][string] $TesseractPath,
        [AllowNull()][string] $GhostscriptPath,
        [bool] $NoGhostscript = $false,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{}
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }
    $missing = [System.Collections.Generic.List[string]]::new()
    $optionalMissing = [System.Collections.Generic.List[string]]::new()

    $pythonPath = if ($PythonRuntime) { $PythonRuntime.Path } else { $null }
    if (-not $pythonPath) { $missing.Add((Get-LocalizedText @localization -Text 'Python interpreter')) }
    if (-not $TesseractPath) { $missing.Add('Tesseract') }

    # Ghostscript is the optional optimization stage after OCRmyPDF.
    $resolvedGhostscriptPath = $null
    if (-not $NoGhostscript) {
        $resolvedGhostscriptPath = $GhostscriptPath
        if (-not $resolvedGhostscriptPath) {
            $optionalMissing.Add((Get-LocalizedText @localization -Text 'Ghostscript (required only with -GhostscriptDpi)'))
        }
    }

    # pngquant is optional for OCRmyPDF optimization and must not block the run.
    # jbig2 is intentionally not used; it is relevant only for monochrome images.
    if ($pythonPath -and -not (Test-PythonModule -PythonPath $pythonPath -ModuleName 'ocrmypdf')) {
        $missing.Add((Get-LocalizedText @localization -Text 'OCRmyPDF (Python module)'))
    }
    if ($pythonPath -and -not (Test-PythonModule -PythonPath $pythonPath -ModuleName 'pikepdf')) {
        $missing.Add((Get-LocalizedText @localization -Text 'pikepdf (Python module)'))
    }

    [pscustomobject]@{
        PythonPath      = $pythonPath
        PythonScope     = if ($PythonRuntime) { $PythonRuntime.Scope } else { $null }
        GhostscriptPath = $resolvedGhostscriptPath
        Missing         = $missing
        OptionalMissing = $optionalMissing
    }
}
