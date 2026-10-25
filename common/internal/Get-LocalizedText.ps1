<#
.SYNOPSIS
    Provides the localized console message lookup shared by all tool folders.

.DESCRIPTION
    Defines Get-LocalizedText. Without explicit -Language and -Messages values, it
    uses the calling script's $script:OutputLanguage and $script:GermanMessages.

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

.PARAMETER Messages
    German catalog keyed by the English source text.

.OUTPUTS
    System.String. The localized and optionally formatted message.
#>
function Get-LocalizedText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [AllowEmptyCollection()][object[]] $Arguments = @(),
        [string] $Language = $script:OutputLanguage,
        [hashtable] $Messages = $script:GermanMessages
    )

    $template = if ($Language -eq 'de' -and $Messages.ContainsKey($Text)) {
        $Messages[$Text]
    }
    else { $Text }
    if ($Arguments.Count -gt 0) { return $template -f $Arguments }
    return $template
}
