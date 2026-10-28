<#
.SYNOPSIS
    Provides the Tesseract helpers for the OCR script.

.DESCRIPTION
    Defines Invoke-Tesseract, which runs the Tesseract executable.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Runs Tesseract with the specified arguments.

.DESCRIPTION
    Starts Tesseract directly and reads redirected output streams asynchronously
    so errors can be evaluated reliably and the pipes do not block.

.PARAMETER TesseractPath
    Path to the Tesseract executable.

.PARAMETER Arguments
    Argument string for Tesseract.

.PARAMETER UiLanguage
    Language of error messages: 'de' selects the German catalog, anything else English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    PSCustomObject with ExitCode, StdOut, and StdErr.
#>
function Invoke-Tesseract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $TesseractPath,
        [Parameter(Mandatory)][string] $Arguments,
        [string] $UiLanguage = 'en',
        [string]$MessagesPath = ''
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $TesseractPath
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw (Get-LocalizedText -Text 'Tesseract could not be started.' -Language $UiLanguage -MessagesPath $MessagesPath)
        }
        # Read asynchronously so large output cannot block the pipe.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdoutTask.GetAwaiter().GetResult()
            StdErr   = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally { $process.Dispose() }
}
