<#
.SYNOPSIS
    Reads date and time metadata from a media file.

.DESCRIPTION
    Defines Get-MediaDateTag, which uses ExifTool to return supported
    file-level and capture date/time tags, excluding file-system timestamps
    and per-track creation/modification timestamps.

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
    Gets embedded date/time tags from a media file.

.DESCRIPTION
    Requests ExifTool's complete Time tag group in grouped JSON form. File
    system timestamps are excluded because they are preserved separately.
    Per-track creation and modification timestamps are excluded because output
    streams may differ from the source. Samsung's maker-note TimeStamp and
    IFD0:ModifyDate are excluded because neither is a reliable capture date.

.PARAMETER Path
    Path to the media file.

.PARAMETER ExifToolPath
    Path to the ExifTool executable.

.PARAMETER UiLanguage
    Language of error messages: 'de' selects German, anything else English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.OUTPUTS
    Hashtable mapping grouped ExifTool file-level and capture date/time tags
    to normalized values.
#>
function Get-MediaDateTag
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $ExifToolPath,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{ }
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }
    $result = Invoke-MediaTool -ExecutablePath $ExifToolPath -Arguments @(
        '-j', '-G1', '-s', '-time:all', '--File:all', $Path
    ) -UiLanguage $UiLanguage -Messages $Messages
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
        throw (Get-LocalizedText @localization -Text 'ExifTool could not read date metadata for {0}: {1}' -Arguments @($Path, $details))
    }

    try
    {
        $parsedMetadata = ConvertFrom-Json -InputObject $result.StdOut -ErrorAction Stop
    }
    catch
    {
        throw (Get-LocalizedText @localization -Text 'ExifTool returned invalid date metadata for {0}: {1}' -Arguments @($Path, $_.Exception.Message))
    }
    if ($parsedMetadata -is [array])
    {
        $records = $parsedMetadata
    }
    else
    {
        $records = @($parsedMetadata)
    }
    if ($records.Count -ne 1)
    {
        throw (Get-LocalizedText @localization -Text 'ExifTool returned an unexpected number of metadata records for {0}.' -Arguments @($Path))
    }

    $metadata = @{ }
    foreach ($property in $records[0].PSObject.Properties)
    {
        if ($property.Name -eq 'SourceFile' -or
                $property.Name -match '^Track\d+:(?:Media|Track)(?:Create|Modify)Date$' -or
                $property.Name -in @('Samsung:TimeStamp', 'IFD0:ModifyDate'))
        {
            continue
        }
        $metadata[$property.Name] = ConvertTo-Json -InputObject $property.Value -Compress -Depth 20
    }
    return $metadata
}
