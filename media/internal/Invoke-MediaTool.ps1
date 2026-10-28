<#
.SYNOPSIS
    Provides redirected process execution for media tools.

.DESCRIPTION
    Defines Invoke-MediaTool, which runs a media executable directly and
    asynchronously reads both output streams.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Uses
    ConvertTo-QuotedArgument and Get-LocalizedText from common\internal.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Runs an external media tool.

.DESCRIPTION
    Starts the executable directly, drains standard output and standard error
    asynchronously, waits for completion, and returns both streams and the
    process exit code.

.PARAMETER ExecutablePath
    Path to the executable.

.PARAMETER Arguments
    Argument list passed to the executable.

.PARAMETER UiLanguage
    Language of error messages: 'de' selects German, anything else English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    PSCustomObject with ExitCode, StdOut, and StdErr.
#>
function Invoke-MediaTool
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ExecutablePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [string] $UiLanguage = 'en',
        [string]$MessagesPath = ''
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $ExecutablePath
    $startInfo.Arguments = ($Arguments | ForEach-Object { ConvertTo-QuotedArgument -Value $_ }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try
    {
        try
        {
            $started = $process.Start()
        }
        catch
        {
            throw (Get-LocalizedText -Text 'Media tool could not be started: {0}' -Arguments @($_.Exception.Message) -Language $UiLanguage -MessagesPath $MessagesPath)
        }
        if (-not $started)
        {
            throw (Get-LocalizedText -Text 'Media tool could not be started: {0}' -Arguments @($ExecutablePath) -Language $UiLanguage -MessagesPath $MessagesPath)
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut = $stdoutTask.GetAwaiter().GetResult()
            StdErr = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally
    {
        $process.Dispose()
    }
}
