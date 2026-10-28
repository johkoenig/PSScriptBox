<#
.SYNOPSIS
    Finds embedded media date tags that need updating.

.DESCRIPTION
    Defines Get-MediaDateUpdateArgument, which reads the legacy date tags and
    returns write arguments only for tags whose value differs from the target.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7 and ExifTool.
    Uses Invoke-MediaTool and Get-LocalizedText.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Gets ExifTool arguments for embedded date tags that need updating.

.DESCRIPTION
    Reads all embedded tags written by the legacy date-restoration flow.
    Returns only unqualified tag assignments for which at least one current
    value is missing or differs from the target date.

.PARAMETER Path
    Path to the media file.

.PARAMETER DateTime
    Target date and time.

.PARAMETER ExifToolPath
    Path to the ExifTool executable.

.PARAMETER UiLanguage
    Language of error messages: 'de' selects German, anything else English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    System.String[] containing only date-tag assignments that need writing.
#>
function Get-MediaDateUpdateArgument
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][datetime] $DateTime,
        [Parameter(Mandatory)][string] $ExifToolPath,
        [string] $UiLanguage = 'en',
        [string]$MessagesPath = ''
    )
    $dateTags = @(
        'DateTimeOriginal',
        'CreateDate',
        'ModifyDate',
        'MediaCreateDate',
        'MediaModifyDate',
        'TrackCreateDate',
        'TrackModifyDate'
    )
    $dateFormat = 'yyyy-MM-dd HH:mm:ss'
    $dateValue = $DateTime.ToString($dateFormat, [System.Globalization.CultureInfo]::InvariantCulture)
    $result = Invoke-MediaTool -ExecutablePath $ExifToolPath -Arguments @(
        '-j', '-G1', '-s', '-d', '%Y-%m-%d %H:%M:%S',
        '-DateTimeOriginal', '-CreateDate', '-ModifyDate',
        '-MediaCreateDate', '-MediaModifyDate', '-TrackCreateDate', '-TrackModifyDate',
        $Path
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
        throw (Get-LocalizedText -Text 'ExifTool could not read date metadata for {0}: {1}' -Arguments @(
            $Path, $details
        ) -Language $UiLanguage -MessagesPath $MessagesPath)
    }

    try
    {
        $parsedMetadata = ConvertFrom-Json -InputObject $result.StdOut -ErrorAction Stop
    }
    catch
    {
        throw (Get-LocalizedText -Text 'ExifTool returned invalid date metadata for {0}: {1}' -Arguments @(
            $Path, $_.Exception.Message
        ) -Language $UiLanguage -MessagesPath $MessagesPath)
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
        throw (Get-LocalizedText -Text 'ExifTool returned an unexpected number of metadata records for {0}.' -Arguments @(
            $Path
        ) -Language $UiLanguage -MessagesPath $MessagesPath)
    }

    $propertiesByTag = @{ }
    foreach ($property in $records[0].PSObject.Properties)
    {
        $tagMatch = [regex]::Match($property.Name, '([^:]+)$')
        if (-not $tagMatch.Success -or $tagMatch.Groups[1].Value -notin $dateTags)
        {
            continue
        }
        $tagName = $tagMatch.Groups[1].Value
        if (-not $propertiesByTag.ContainsKey($tagName))
        {
            $propertiesByTag[$tagName] = @()
        }
        $propertiesByTag[$tagName] += $property.Value
    }

    foreach ($dateTag in $dateTags)
    {
        $currentValues = @($propertiesByTag[$dateTag])
        if ($currentValues.Count -eq 0 -or
                @($currentValues | Where-Object { [string]$_ -ne $dateValue }).Count -gt 0)
        {
            "-$dateTag=$dateValue"
        }
    }
}
