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
# Copyright (c) 2026 PSScriptBox contributors
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

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    System.String. The localized status label.
#>
function Get-ToolStatusLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool] $Available,
        [string] $Path,
        [string] $UiLanguage = 'en',
        [string]$MessagesPath = ''
    )
    if ($Available)
    {
        return Get-LocalizedText -Text 'Present' -Language $UiLanguage -MessagesPath $MessagesPath
    }
    if ($Path)
    {
        return Get-LocalizedText -Text 'Found but failed its validation check' -Language $UiLanguage -MessagesPath $MessagesPath
    }
    return Get-LocalizedText -Text 'Missing' -Language $UiLanguage -MessagesPath $MessagesPath
}
