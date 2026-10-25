<#
.SYNOPSIS
    Provides the Python process helper for the PDF scripts.

.DESCRIPTION
    Defines Invoke-PythonCommand, which runs a Python interpreter with an
    argument array and returns its exit code and both output streams.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Requires
    ConvertTo-QuotedArgument and Get-LocalizedText to be dot-sourced by the caller.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Runs Python with the specified arguments.

.DESCRIPTION
    Starts Python directly, reads standard output and error asynchronously, and
    returns both streams with the exit code. The process is started directly
    rather than through a launcher so that the exit code belongs to Python.

.PARAMETER PythonPath
    Path to the Python interpreter.

.PARAMETER Arguments
    Argument list for the Python process.

.PARAMETER UiLanguage
    'de' selects German messages; any other value selects English.

.PARAMETER Messages
    German catalog keyed by the English source text.

.OUTPUTS
    PSCustomObject with ExitCode, StdOut, and StdErr.
#>
function Invoke-PythonCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{}
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $PythonPath
    $startInfo.Arguments = ($Arguments | ForEach-Object { ConvertTo-QuotedArgument -Value $_ }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw (Get-LocalizedText @localization -Text 'Python could not be started: {0}' -Arguments @($PythonPath))
        }

        # Start the reads before WaitForExit so a full output pipe cannot block the process.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdoutTask.GetAwaiter().GetResult()
            StdErr   = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}
