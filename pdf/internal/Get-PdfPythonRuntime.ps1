<#
.SYNOPSIS
    Provides a consistent Python interpreter resolver for the PDF scripts.

.DESCRIPTION
    Prefers a working Python interpreter installed in the current user's
    profile. If none is available, it uses a working machine-wide interpreter.
    The Python launcher is used only to discover an interpreter; callers always
    receive the resolved python.exe path.

.EXAMPLE
    . .\internal\Get-PdfPythonRuntime.ps1
    $runtime = Get-PdfPythonRuntime
    & $runtime.Path --version

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7 and Python 3.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Runs a Python executable and captures its output.

.DESCRIPTION
    Starts a process with redirected streams and reads both asynchronously to
    avoid pipe deadlocks while probing candidate Python installations.

.PARAMETER FilePath
    Executable path to run.

.PARAMETER Arguments
    Arguments passed to the executable.

.OUTPUTS
    PSCustomObject with ExitCode, StdOut, and StdErr.
#>
function Invoke-PdfPythonProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = ($Arguments | ForEach-Object {
        $argument = [string]$_
        '"' + ($argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
    }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            return [pscustomobject]@{ ExitCode = -1; StdOut = ''; StdErr = 'Process did not start.' }
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
    catch {
        return [pscustomobject]@{ ExitCode = -1; StdOut = ''; StdErr = $_.Exception.Message }
    }
    finally {
        $process.Dispose()
    }
}

<#
.SYNOPSIS
    Resolves the preferred usable Python interpreter.

.DESCRIPTION
    Checks directly reachable python.exe candidates first and prefers one
    located in the current user's profile. It uses py.exe only as a fallback
    discovery mechanism, then returns the resolved interpreter executable.
    When PreferredPath is specified, only that exact interpreter is tested.

.PARAMETER PreferredPath
    Optional interpreter path to validate instead of discovering candidates.

.OUTPUTS
    PSCustomObject with Path, Scope, and Discovery, or $null if none works.
#>
function Get-PdfPythonRuntime {
    [CmdletBinding()]
    param([string] $PreferredPath)

    $candidates = [System.Collections.Generic.List[object]]::new()
    if ($PreferredPath) {
        $candidates.Add([pscustomobject]@{ Launcher = $PreferredPath; Arguments = @(); Discovery = 'Explicit path' })
    }
    else {
        foreach ($commandName in @('python.exe', 'python')) {
            foreach ($command in @(Get-Command -Name $commandName -All -ErrorAction SilentlyContinue)) {
                if ($command.CommandType -eq [System.Management.Automation.CommandTypes]::Application -and $command.Source) {
                    if ($command.Source -match '\\WindowsApps\\') { continue }
                    if (-not ($candidates | Where-Object { $_.Launcher -ieq $command.Source })) {
                        $candidates.Add([pscustomobject]@{
                            Launcher  = $command.Source
                            Arguments = @()
                            Discovery = 'python.exe'
                        })
                    }
                }
            }
        }

        foreach ($command in @(Get-Command -Name 'py.exe', 'py' -All -ErrorAction SilentlyContinue)) {
            if ($command.CommandType -eq [System.Management.Automation.CommandTypes]::Application -and $command.Source) {
                if (-not ($candidates | Where-Object { $_.Launcher -ieq $command.Source -and $_.Arguments.Count -eq 0 })) {
                    $candidates.Add([pscustomobject]@{
                        Launcher  = $command.Source
                        Arguments = @()
                        Discovery = 'py.exe launcher'
                    })
                }
                if (-not ($candidates | Where-Object { $_.Launcher -ieq $command.Source -and $_.Arguments -contains '-3' })) {
                    $candidates.Add([pscustomobject]@{
                        Launcher  = $command.Source
                        Arguments = @('-3')
                        Discovery = 'py.exe launcher'
                    })
                }
            }
        }
    }

    $working = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in $candidates) {
        $probe = Invoke-PdfPythonProbe -FilePath $candidate.Launcher -Arguments (
            @($candidate.Arguments) + @('-c', 'import sys; print(sys.executable); print(sys.version_info[0])')
        )
        if ($probe.ExitCode -ne 0) { continue }

        $probeLines = @($probe.StdOut -split '\r?\n' | ForEach-Object { $_.Trim() })
        if ($probeLines -notcontains '3') { continue }
        $resolvedPath = $probeLines | Where-Object { $_ -match '^[A-Za-z]:\\' } | Select-Object -First 1
        if (-not $resolvedPath -or -not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) { continue }

        $scope = 'Machine'
        $userRoots = @(
            [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile),
            [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData),
            [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
        ) | Where-Object { $_ }
        foreach ($root in $userRoots) {
            $normalizedRoot = [System.IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
            $normalizedPath = [System.IO.Path]::GetFullPath($resolvedPath)
            if ($normalizedPath.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                $scope = 'User'
                break
            }
        }

        $working.Add([pscustomobject]@{
            Path      = $resolvedPath
            Scope     = $scope
            Discovery = $candidate.Discovery
        })
    }

    $userRuntime = $working | Where-Object Scope -eq 'User' | Select-Object -First 1
    if ($userRuntime) { return $userRuntime }
    return $working | Select-Object -First 1
}
