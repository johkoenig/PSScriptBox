<#
.SYNOPSIS
    Provides the elevation helper for the PDF processor setup.

.DESCRIPTION
    Defines Start-ElevatedSetup, which restarts the setup script with administrator
    rights and waits for the elevated process.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Requires
    ConvertTo-QuotedArgument and Get-ExecutablePath from the same internal folder.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Restarts the setup script with administrator privileges.

.DESCRIPTION
    Starts a new elevated PowerShell process running the given script with the
    -ElevatedChild switch, and waits for it to finish. This is the only side
    effect that triggers a UAC prompt.

.PARAMETER ScriptPath
    Path of the setup script to run in the elevated process.

.PARAMETER EnglishOutput
    Preserves the request for English output in the elevated process.

.PARAMETER RuntimePythonPath
    Preserves the selected interpreter path in the elevated process.

.OUTPUTS
    System.Int32. The elevated process exit code.
#>
function Start-ElevatedSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ScriptPath,
        [Parameter(Mandatory)][bool] $EnglishOutput,
        [string] $RuntimePythonPath
    )

    $hostName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $hostPath = Get-ExecutablePath -Name $hostName
    if (-not $hostPath) { $hostPath = Join-Path $PSHOME $hostName }

    $childArguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $ScriptPath
        '-ElevatedChild'
    )
    if ($EnglishOutput) { $childArguments += '-EnglishOutput' }
    if ($RuntimePythonPath) { $childArguments += @('-RuntimePythonPath', $RuntimePythonPath) }
    $argumentLine = ($childArguments | ForEach-Object { ConvertTo-QuotedArgument -Value $_ }) -join ' '
    $childProcess = Start-Process -FilePath $hostPath -Verb RunAs -ArgumentList $argumentLine -Wait -PassThru
    return $childProcess.ExitCode
}
