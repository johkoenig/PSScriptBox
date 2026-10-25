<#
.SYNOPSIS
    Provides the tool location lookup for the PDF processor setup.

.DESCRIPTION
    Defines Get-PdfToolLocation, which resolves the executable paths that the
    setup checks, once per lookup pass.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Requires
    Get-PdfPythonRuntime, Get-ExecutablePath, and Get-GhostscriptExecutablePath
    from the same internal folder.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Locates the executables used by the PDF processor setup.

.DESCRIPTION
    Looks up Chocolatey, the preferred or discovered Python interpreter, Tesseract,
    and Ghostscript. Paths are returned as found in the current PATH; no tool is
    executed by this function apart from the Python interpreter probe.

.PARAMETER PreferredPythonPath
    Optional Python interpreter path. When empty, the interpreter is discovered.

.OUTPUTS
    PSCustomObject with ChocolateyPath, PythonPath, PythonScope, TesseractPath,
    and GhostscriptPath. Missing tools are $null.
#>
function Get-PdfToolLocation {
    [CmdletBinding()]
    param([string] $PreferredPythonPath = '')

    $pythonRuntime = Get-PdfPythonRuntime -PreferredPath $PreferredPythonPath
    $pythonPath = $null
    $pythonScope = $null
    if ($pythonRuntime) {
        $pythonPath = $pythonRuntime.Path
        $pythonScope = $pythonRuntime.Scope
    }

    return [pscustomobject]@{
        ChocolateyPath  = Get-ExecutablePath -Name 'choco'
        PythonPath      = $pythonPath
        PythonScope     = $pythonScope
        TesseractPath   = Get-ExecutablePath -Name 'tesseract'
        GhostscriptPath = Get-GhostscriptExecutablePath
    }
}
