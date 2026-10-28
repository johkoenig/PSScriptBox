<#
.SYNOPSIS
    Renames a media file and restores its dates.

.DESCRIPTION
    Defines Invoke-MediaDateRestoration, which renames a file when required,
    and updates only filesystem and embedded dates that differ from the target.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7 and ExifTool.
    Uses Invoke-MediaTool and Get-LocalizedText.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Renames a media file and updates its filesystem and embedded dates.

.DESCRIPTION
    Preserves the legacy date tags and operation behavior while comparing
    current values first. Unchanged filesystem timestamps and metadata tags are
    not written. Last-access time is not changed.

.PARAMETER File
    Source media file.

.PARAMETER TargetPath
    Unique target path in the source directory.

.PARAMETER DateTime
    Date and time to apply.

.PARAMETER ExifToolPath
    Path to the ExifTool executable.

.PARAMETER UiLanguage
    Language of error messages: 'de' selects German, anything else English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    PSCustomObject with FilePath and WarningMessages properties.
#>
function Invoke-MediaDateRestoration
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $File,
        [Parameter(Mandatory)][string] $TargetPath,
        [Parameter(Mandatory)][datetime] $DateTime,
        [Parameter(Mandatory)][string] $ExifToolPath,
        [string] $UiLanguage = 'en',
        [string]$MessagesPath = ''
    )
    $targetName = [System.IO.Path]::GetFileName($TargetPath)
    if (-not [string]::Equals($File.FullName, $TargetPath, [System.StringComparison]::Ordinal))
    {
        Rename-Item -LiteralPath $File.FullName -NewName $targetName -ErrorAction Stop
    }

    $updateFailure = $null
    $timestampFailures = @()
    $warningMessages = @()
    $dateArguments = @()
    try
    {
        $dateArguments = @(
            Get-MediaDateUpdateArgument -Path $TargetPath -DateTime $DateTime `
                -ExifToolPath $ExifToolPath -UiLanguage $UiLanguage -MessagesPath $MessagesPath
        )
        if ($dateArguments.Count -gt 0)
        {
            $arguments = @('-overwrite_original') + $dateArguments + @($TargetPath)
            $result = Invoke-MediaTool -ExecutablePath $ExifToolPath -Arguments $arguments `
                -UiLanguage $UiLanguage -MessagesPath $MessagesPath
            $outputLines = @(
            @($result.StdOut -split "`r?`n") + @($result.StdErr -split "`r?`n") |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
            if ($result.ExitCode -ne 0)
            {
                $details = $outputLines -join [Environment]::NewLine
                $updateFailure = Get-LocalizedText -Text 'ExifTool failed to update date metadata for {0} (exit code {1}): {2}' -Arguments @(
                    $TargetPath, $result.ExitCode, $details
                ) -Language $UiLanguage -MessagesPath $MessagesPath
            }
            else
            {
                $warningMessages = @($outputLines | Where-Object { $_ -notmatch '(?i)minor|not defined|Nothing to do' })
            }
        }
    }
    catch
    {
        $updateFailure = $_.Exception.Message
    }

    try
    {
        if ([System.IO.File]::GetCreationTime($TargetPath) -ne $DateTime)
        {
            [System.IO.File]::SetCreationTime($TargetPath, $DateTime)
        }
    }
    catch
    {
        $timestampFailures += Get-LocalizedText -Text 'Could not set CreationTime for {0}: {1}' -Arguments @(
            $TargetPath, $_.Exception.Message
        ) -Language $UiLanguage -MessagesPath $MessagesPath
    }
    try
    {
        if ([System.IO.File]::GetLastWriteTime($TargetPath) -ne $DateTime)
        {
            [System.IO.File]::SetLastWriteTime($TargetPath, $DateTime)
        }
    }
    catch
    {
        $timestampFailures += Get-LocalizedText -Text 'Could not set LastWriteTime for {0}: {1}' -Arguments @(
            $TargetPath, $_.Exception.Message
        ) -Language $UiLanguage -MessagesPath $MessagesPath
    }

    if ($updateFailure -and $timestampFailures.Count -gt 0)
    {
        throw (Get-LocalizedText -Text '{0}; {1}' -Arguments @(
            $updateFailure, ($timestampFailures -join [Environment]::NewLine)
        ) -Language $UiLanguage -MessagesPath $MessagesPath)
    }
    if ($updateFailure)
    {
        throw $updateFailure
    }
    if ($timestampFailures.Count -gt 0)
    {
        throw ($timestampFailures -join [Environment]::NewLine)
    }

    [pscustomobject]@{
        FilePath = $TargetPath
        WarningMessages = $warningMessages
    }
}
