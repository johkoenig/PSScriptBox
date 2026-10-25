<#
.SYNOPSIS
    Provides the external process runner for the PDF processor setup.

.DESCRIPTION
    Defines Invoke-SetupProcess, which runs an executable with redirected output
    and error streams and returns its exit code and captured text.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Requires
    ConvertTo-QuotedArgument from the same internal folder.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Runs an external program and captures its output.

.DESCRIPTION
    Starts the specified executable with redirected streams and reads both
    streams asynchronously to avoid pipe deadlocks.

.PARAMETER FilePath
    Executable path.

.PARAMETER Arguments
    Argument list for the executable. Each value is quoted before the process
    starts.

.PARAMETER UiLanguage
    'de' selects German messages; any other value selects English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.OUTPUTS
    PSCustomObject with ExitCode, StdOut, and StdErr.
#>
function Invoke-SetupProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{}
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }

    # ProcessStartInfo is used directly instead of Start-Process so that stderr
    # stays a plain string and is not turned into a PowerShell error record.
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = ($Arguments | ForEach-Object { ConvertTo-QuotedArgument -Value $_ }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw (Get-LocalizedText @localization -Text 'Could not start process: {0}' -Arguments @($FilePath))
        }
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
