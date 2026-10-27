<#
.SYNOPSIS
    Creates a unique date-based media filename.

.DESCRIPTION
    Defines New-MediaDateFileName, which builds the legacy camera-roll date
    pattern with a random uppercase code and avoids existing paths.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
    Uses New-MediaDateCode and Get-LocalizedText.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Creates an available date-based filename.

.DESCRIPTION
    Formats a timestamp as YY-MM-DD HH-mm-ss, adds a random four-character
    uppercase code, and generates another code if the target path already exists.

.PARAMETER DateTime
    Date and time to encode in the filename.

.PARAMETER DirectoryPath
    Directory where the file will be renamed.

.PARAMETER Extension
    Original file extension, including the leading dot.

.PARAMETER UiLanguage
    Language of error messages: 'de' selects German, anything else English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.OUTPUTS
    PSCustomObject with FileName and FullPath properties.
#>
function New-MediaDateFileName
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime] $DateTime,
        [Parameter(Mandatory)][string] $DirectoryPath,
        [Parameter(Mandatory)][string] $Extension,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{ }
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }
    $datePrefix = $DateTime.ToString('yy-MM-dd HH-mm-ss', [System.Globalization.CultureInfo]::InvariantCulture)
    for ($attempt = 0; $attempt -lt 100; $attempt++)
    {
        $fileName = '{0} {1}{2}' -f $datePrefix, (New-MediaDateCode), $Extension
        $fullPath = Join-Path -Path $DirectoryPath -ChildPath $fileName
        if (-not (Test-Path -LiteralPath $fullPath))
        {
            return [pscustomobject]@{
                FileName = $fileName
                FullPath = $fullPath
            }
        }
    }

    throw (Get-LocalizedText @localization -Text 'Could not generate a unique filename for {0}.' -Arguments @($DirectoryPath))
}
