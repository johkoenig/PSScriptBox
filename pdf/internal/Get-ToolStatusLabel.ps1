<#
.SYNOPSIS
    Provides the status label helper for the PDF processor setup report.

.DESCRIPTION
    Defines Get-ToolStatusLabel, which turns an availability flag and a located
    path into a localized status word.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Requires
    Get-LocalizedText from the same internal folder.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Returns the localized status of one tool.

.DESCRIPTION
    Returns "Present" when the tool passed its validation check, "Found but
    failed its validation check" when a path exists but the check failed, and
    "Missing" when no path was located.

.PARAMETER Available
    $true when the tool passed its validation check.

.PARAMETER Path
    Located executable path, or empty when the tool was not found.

.PARAMETER UiLanguage
    'de' selects German messages; any other value selects English.

.PARAMETER Messages
    German message catalog keyed by the English source text.

.OUTPUTS
    System.String. The localized status label.
#>
function Get-ToolStatusLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool] $Available,
        [string] $Path,
        [string] $UiLanguage = 'en',
        [hashtable] $Messages = @{}
    )

    $localization = @{ Language = $UiLanguage; Messages = $Messages }
    if ($Available) { return Get-LocalizedText @localization -Text 'Present' }
    if ($Path) { return Get-LocalizedText @localization -Text 'Found but failed its validation check' }
    return Get-LocalizedText @localization -Text 'Missing'
}
