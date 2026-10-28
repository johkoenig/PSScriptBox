<#
.SYNOPSIS
    Finds the best available date for a media file.

.DESCRIPTION
    Defines Get-MediaDateSource, which checks the filename first, then the
    DateTimeOriginal EXIF tag, followed by CreateDate and ModifyDate metadata.

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
    Gets the date and source selected for a media file.

.DESCRIPTION
    Uses a leading YY-MM-DD HH-mm-ss filename timestamp when present. Otherwise
    queries DateTimeOriginal, CreateDate, and ModifyDate in that order. A
    malformed filename timestamp is an error and does not fall back to metadata.

.PARAMETER File
    Media file whose date is resolved.

.PARAMETER ExifToolPath
    Path to the ExifTool executable.

.PARAMETER UiLanguage
    Language of error messages: 'de' selects German, anything else English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    PSCustomObject with DateTime and Source properties.
#>
function Get-MediaDateSource
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $File,
        [Parameter(Mandatory)][string] $ExifToolPath,
        [string] $UiLanguage = 'en',
        [string]$MessagesPath = ''
    )
    $filenameMatch = [regex]::Match($File.Name, '^(\d{2}-\d{2}-\d{2} \d{2}-\d{2}-\d{2})')
    if ($filenameMatch.Success)
    {
        $isFileNameFormatted = [regex]::IsMatch(
                [System.IO.Path]::GetFileNameWithoutExtension($File.Name),
                '^\d{2}-\d{2}-\d{2} \d{2}-\d{2}-\d{2} [0-9A-Z]{4}$'
        )
        $parts = $filenameMatch.Groups[1].Value -split '[- ]'
        try
        {
            $dateTime = [datetime]::new(
                    (2000 + [int]$parts[0]),
                    [int]$parts[1],
                    [int]$parts[2],
                    [int]$parts[3],
                    [int]$parts[4],
                    [int]$parts[5]
            )
        }
        catch
        {
            throw (Get-LocalizedText -Text 'Invalid date in filename: {0}' -Arguments @($File.Name) -Language $UiLanguage -MessagesPath $MessagesPath)
        }

        return [pscustomobject]@{
            DateTime = $dateTime
            Source = 'filename'
            IsFileNameFormatted = $isFileNameFormatted
        }
    }

    $dateTags = @(
        [pscustomobject]@{ Name = 'DateTimeOriginal'; Source = 'EXIF DateTimeOriginal' }
        [pscustomobject]@{ Name = 'CreateDate'; Source = 'CreateDate' }
        [pscustomobject]@{ Name = 'ModifyDate'; Source = 'ModifyDate' }
    )
    foreach ($dateTag in $dateTags)
    {
        $result = Invoke-MediaTool -ExecutablePath $ExifToolPath -Arguments @(
            '-s', '-s', '-s', '-d', '%Y-%m-%d %H:%M:%S', "-$( $dateTag.Name )", $File.FullName
        ) -UiLanguage $UiLanguage -MessagesPath $MessagesPath
        if ($result.ExitCode -ne 0)
        {
            $details = if ( [string]::IsNullOrWhiteSpace($result.StdErr))
            {
                $result.StdOut.Trim()
            }
            else
            {
                $result.StdErr.Trim()
            }
            throw (Get-LocalizedText -Text 'ExifTool failed to read date tag {0} for {1} (exit code {2}): {3}' -Arguments @(
                $dateTag.Name, $File.FullName, $result.ExitCode, $details
            ) -Language $UiLanguage -MessagesPath $MessagesPath)
        }

        $dateValue = @(
        $result.StdOut -split "`r?`n" |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -First 1
        )
        if ($dateValue.Count -eq 0)
        {
            continue
        }

        try
        {
            $dateTime = [datetime]::ParseExact(
                    $dateValue[0].Trim(),
                    'yyyy-MM-dd HH:mm:ss',
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::None
            )
        }
        catch
        {
            throw (Get-LocalizedText -Text 'Invalid date in metadata tag {0} for {1}: {2}' -Arguments @(
                $dateTag.Name, $File.Name,$dateValue[0].Trim()
            ) -Language $UiLanguage -MessagesPath $MessagesPath)
        }

        return [pscustomobject]@{
            DateTime = $dateTime
            Source = $dateTag.Source
            IsFileNameFormatted = $false
        }
    }

    throw (Get-LocalizedText -Text 'No valid date found for {0} in filename or metadata.' -Arguments @($File.Name) -Language $UiLanguage -MessagesPath $MessagesPath)
}
