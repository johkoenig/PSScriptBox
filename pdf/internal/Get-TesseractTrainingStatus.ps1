<#
.SYNOPSIS
    Provides the Tesseract language data inspection for the PDF processor setup.

.DESCRIPTION
    Defines Get-TesseractTrainingStatus, which reads the installed Tesseract
    language codes and the tessdata folder without changing anything.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Requires
    Invoke-SetupProcess from the same internal folder.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Gets Tesseract's installed language data.

.DESCRIPTION
    Runs `tesseract --list-langs` and returns the available language codes and
    the local tessdata directory. When Tesseract does not report its tessdata
    path, the tessdata folder next to the executable is used.

.PARAMETER TesseractPath
    Path to the Tesseract executable.

.PARAMETER UiLanguage
    'de' selects German messages; any other value selects English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    PSCustomObject with Languages, TessdataPath, and CheckSucceeded.
#>
function Get-TesseractTrainingStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $TesseractPath,
        [string] $UiLanguage = 'en',
        [string]$MessagesPath = ''
    )

    $processOptions = @{ UiLanguage = $UiLanguage; MessagesPath = $MessagesPath }
    $result = Invoke-SetupProcess -FilePath $TesseractPath -Arguments @('--list-langs') @processOptions
    if ($result.ExitCode -ne 0) {
        return [pscustomobject]@{
            Languages      = @()
            TessdataPath   = $null
            CheckSucceeded = $false
        }
    }

    $tessdataPath = $null
    if ($result.StdOut -match 'List of available languages in "([^"]+)"') {
        $tessdataPath = $Matches[1]
    }
    if (-not $tessdataPath) {
        $tessdataPath = Join-Path -Path (Split-Path -Parent $TesseractPath) -ChildPath 'tessdata'
    }

    $languages = @(
        $result.StdOut -split '\r?\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^[A-Za-z0-9_]+$' }
    )
    return [pscustomobject]@{
        Languages      = $languages
        TessdataPath   = $tessdataPath
        CheckSucceeded = $true
    }
}
