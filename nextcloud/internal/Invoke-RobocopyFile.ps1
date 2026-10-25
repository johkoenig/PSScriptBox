<#
.SYNOPSIS
    Provides the single-file Robocopy helper for the Nextcloud scripts.

.DESCRIPTION
    Defines Invoke-RobocopyFile. Requires Get-LocalizedText.ps1 from the same
    folder and robocopy.exe from Windows.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Runs Robocopy for one file while reporting live progress.

.DESCRIPTION
    Uses restartable mode, bounded retries, data/attribute/time copying, and
    asynchronous stream reading to keep Robocopy output from blocking.
    Robocopy is started through System.Diagnostics.Process so its output can be
    read line by line while the copy runs. Progress is passed to the
    ProgressReporter callback, so this function writes nothing to the console.

.PARAMETER SourceDirectory
    Directory containing the source file.

.PARAMETER DestinationDirectory
    Existing or newly created destination directory.

.PARAMETER FileName
    Name of the file to copy.

.PARAMETER RelativePath
    File path relative to the selected user folder, used in progress and errors.

.PARAMETER FileLength
    Expected source file length.

.PARAMETER CompletedBytes
    Bytes already skipped or copied within the selected folder.

.PARAMETER TotalBytes
    Total source bytes in the selected folder.

.PARAMETER FolderName
    Display name of the selected user folder.

.PARAMETER Language
    'de' selects German messages; any other value selects English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.PARAMETER ProgressReporter
    Callback invoked with -Activity, -Status, and -PercentComplete for each
    progress line Robocopy reports. The default callback does nothing.

.OUTPUTS
    None. Throws when Robocopy fails or the destination file does not exist afterwards.

.NOTES
    Robocopy exit codes 8 and higher indicate failure.
#>
function Invoke-RobocopyFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $SourceDirectory,
        [Parameter(Mandatory)][string] $DestinationDirectory,
        [Parameter(Mandatory)][string] $FileName,
        [Parameter(Mandatory)][string] $RelativePath,
        [Parameter(Mandatory)][long] $FileLength,
        [Parameter(Mandatory)][long] $CompletedBytes,
        [Parameter(Mandatory)][long] $TotalBytes,
        [Parameter(Mandatory)][string] $FolderName,
        [string] $Language = 'en',
        [hashtable] $Messages = @{},
        [scriptblock] $ProgressReporter = { param([string] $Activity, [string] $Status, [int] $PercentComplete, [switch] $Completed) }
    )

    $robocopy = Get-Command -Name 'robocopy.exe' -CommandType Application -ErrorAction Stop
    [System.IO.Directory]::CreateDirectory($DestinationDirectory) | Out-Null

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $robocopy.Source
    $startInfo.Arguments = '"{0}" "{1}" "{2}" /Z /R:2 /W:1 /COPY:DAT /DCOPY:DAT /XJ /IS /IT' -f @(
        $SourceDirectory, $DestinationDirectory, $FileName
    )
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $outputLines = [System.Collections.Generic.List[string]]::new()
    $errorLines = [System.Collections.Generic.List[string]]::new()
    $activity = Get-LocalizedText -Text 'Copying folder {0}' -Arguments @($FolderName) -Language $Language -Messages $Messages
    $status = Get-LocalizedText -Text 'Copying file: {0}' -Arguments @($RelativePath) -Language $Language -Messages $Messages

    try {
        if (-not $process.Start()) {
            throw (Get-LocalizedText -Text 'Could not start Robocopy for {0}.' -Arguments @($RelativePath) `
                    -Language $Language -Messages $Messages)
        }
        $standardOutputTask = $process.StandardOutput.ReadLineAsync()
        $standardErrorTask = $process.StandardError.ReadLineAsync()
        $standardOutputEnded = $false
        $standardErrorEnded = $false

        while (-not $process.HasExited -or -not $standardOutputEnded -or -not $standardErrorEnded) {
            $receivedLine = $false
            if (-not $standardOutputEnded -and $standardOutputTask.IsCompleted) {
                $line = $standardOutputTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $standardOutputEnded = $true
                }
                else {
                    if ($outputLines.Count -ge 12) { $outputLines.RemoveAt(0) }
                    $outputLines.Add($line)
                    if ($line -match '^\s*(\d+(?:[\.,]\d+)?)%\s*$') {
                        $filePercent = [double]::Parse(
                            $matches[1].Replace(',', '.'),
                            [System.Globalization.CultureInfo]::InvariantCulture
                        )
                        if ($TotalBytes -gt 0) {
                            $overallPercent = (($CompletedBytes + ($FileLength * $filePercent / 100)) / $TotalBytes) * 100
                        }
                        else {
                            $overallPercent = $filePercent
                        }
                        & $ProgressReporter -Activity $activity -Status $status `
                            -PercentComplete ([Math]::Min(100, [Math]::Max(0, [int]$overallPercent)))
                    }
                    $standardOutputTask = $process.StandardOutput.ReadLineAsync()
                }
                $receivedLine = $true
            }

            if (-not $standardErrorEnded -and $standardErrorTask.IsCompleted) {
                $line = $standardErrorTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $standardErrorEnded = $true
                }
                else {
                    if ($errorLines.Count -ge 12) { $errorLines.RemoveAt(0) }
                    $errorLines.Add($line)
                    $standardErrorTask = $process.StandardError.ReadLineAsync()
                }
                $receivedLine = $true
            }

            if (-not $receivedLine) { Start-Sleep -Milliseconds 50 }
        }
        $process.WaitForExit()

        if ($process.ExitCode -ge 8) {
            $details = @($errorLines.ToArray()) + @($outputLines.ToArray())
            $details = (($details | Select-Object -Last 8) -join ' ').Trim()
            if ([string]::IsNullOrWhiteSpace($details)) {
                $details = Get-LocalizedText -Text 'No diagnostic output was returned.' -Language $Language -Messages $Messages
            }
            throw (Get-LocalizedText -Text 'Robocopy failed for {0} (exit code {1}): {2}' -Arguments @(
                    $RelativePath, $process.ExitCode, $details
                ) -Language $Language -Messages $Messages)
        }
    }
    finally {
        $process.Dispose()
    }

    $destinationFilePath = Join-Path $DestinationDirectory $FileName
    if (-not (Test-Path -LiteralPath $destinationFilePath -PathType Leaf)) {
        throw (Get-LocalizedText -Text 'Robocopy did not create the destination file: {0}' -Arguments @($RelativePath) `
                -Language $Language -Messages $Messages)
    }
}
