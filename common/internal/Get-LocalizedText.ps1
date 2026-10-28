<#
.SYNOPSIS
    Provides the localized console message lookup shared by all tool folders.

.DESCRIPTION
    Defines Get-LocalizedText. Without an explicit -Language value, it uses the
    current UI culture. The German catalog is loaded from -MessagesPath when
    German is selected.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Returns a localized console message.

.DESCRIPTION
    Uses the German message catalog when German output is selected; otherwise
    returns the English source string. Formats the selected template when
    formatting arguments are provided.

.PARAMETER Text
    English source message and lookup key.

.PARAMETER Arguments
    Optional values used to format placeholders in the message.

.PARAMETER Language
    'de' selects the German catalog; any other value selects English.

.PARAMETER MessagesPath
    Path to the German message catalog. Required when German output is selected.

.OUTPUTS
    System.String. The localized and optionally formatted message.
#>
function Get-LocalizedText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [AllowEmptyCollection()][object[]] $Arguments = @(),
        [string] $Language,
        [string] $MessagesPath
    )

    $effectiveLanguage = if ( $PSBoundParameters.ContainsKey('Language'))
    {
        $Language
    }
    else
    {
        [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
    }

    $template = $Text
    if ($effectiveLanguage -eq 'de')
    {
        if ( [string]::IsNullOrWhiteSpace($MessagesPath))
        {
            throw 'MessagesPath is required when German output is selected.'
        }

        $catalogPath = [System.IO.Path]::GetFullPath($MessagesPath)
        if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf))
        {
            throw "The German message catalog was not found: $catalogPath"
        }

        $messages = Import-PowerShellDataFile -LiteralPath $catalogPath
        if ( $messages.ContainsKey($Text))
        {
            $template = $messages[$Text]
        }
    }

    if ($Arguments.Count -gt 0) { return $template -f $Arguments }
    return $template
}
