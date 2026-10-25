<#
.SYNOPSIS
    Removes original PDF backups when the processed PDF exists.

.DESCRIPTION
    Recursively searches a folder for PDF files with the _orig suffix before the
    extension. A backup is deleted only when the corresponding processed PDF
    without the _orig suffix exists in the same folder. Use -WhatIf to preview
    the deletion list safely.

.PARAMETER InputPath
    Folder to search recursively for matching _orig PDFs. If omitted, the path
    is requested interactively.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.EXAMPLE
    .\Clean-OriginalPdfs.ps1
    Prompts for a folder.

.EXAMPLE
    .\Clean-OriginalPdfs.ps1 -InputPath 'C:\PDFs' -WhatIf
    Previews which _orig files would be deleted.

.EXAMPLE
    .\Clean-OriginalPdfs.ps1 -InputPath 'C:\PDFs'
    Prompts for confirmation before deleting each matching _orig file.

.NOTES
    Dependencies: PowerShell 5.1 or later. No additional programs or modules
    are required.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string] $InputPath,

    [switch] $EnglishOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:OutputLanguage = if (
    $EnglishOutput -or [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'de'
) { 'en' } else { 'de' }
$script:GermanMessages = if ($script:OutputLanguage -eq 'de') {
    Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'Localization\de-DE\Messages.psd1')
}
else { @{} }

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

.OUTPUTS
    System.String. The localized and optionally formatted message.
#>
function Get-LocalizedText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [AllowEmptyCollection()][object[]] $Arguments = @()
    )

    $template = if ($script:OutputLanguage -eq 'de' -and $script:GermanMessages.ContainsKey($Text)) {
        $script:GermanMessages[$Text]
    }
    else { $Text }
    if ($Arguments.Count -gt 0) { return $template -f $Arguments }
    return $template
}

$headerLines = @(
    '       .-------------------------------------------.'
    '      /                                           /|'
    '     /___________________________________________/ |'
    '     |  .-------------------------------------.  | |'
    '     |  | PDF BACKUP CLEANUP                  |  | |'
    '     |  | VERIFY / REMOVE _ORIG               |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)

Write-Host ''
foreach ($headerLine in $headerLines) {
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText 'Removes eligible original PDF backups.') -ForegroundColor Cyan
Write-Host ''

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    Write-Host (Get-LocalizedText 'Enter the folder containing original PDF backups.')
    $InputPath = Read-Host -Prompt (Get-LocalizedText 'InputPath')
}
if ([string]::IsNullOrWhiteSpace($InputPath)) {
    throw (Get-LocalizedText 'No folder was specified.')
}

$InputPath = [Environment]::ExpandEnvironmentVariables($InputPath.Trim().Trim('"'))
if (-not (Test-Path -LiteralPath $InputPath -PathType Container)) {
    throw (Get-LocalizedText -Text 'The specified folder was not found: {0}' -Arguments @($InputPath))
}

$directory = Get-Item -LiteralPath $InputPath
$basePathPrefix = $directory.FullName
if (-not $basePathPrefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar)) {
    $basePathPrefix += [System.IO.Path]::DirectorySeparatorChar
}
$pathSegments = @($directory.FullName.TrimEnd('\') -split '[\\/]' | Where-Object { $_ })
$pathTail = @($pathSegments | Select-Object -Last 3)
$summaryPath = if ($pathTail.Count -gt 0) { '.\' + ($pathTail -join '\') + '\' } else { '.\' }
$originalFiles = @(Get-ChildItem -LiteralPath $directory.FullName -File -Recurse -Force |
    Where-Object { $_.Extension -ieq '.pdf' -and $_.BaseName -match '_orig$' })

$eligibleFiles = @(
    foreach ($originalFile in $originalFiles) {
        $processedBaseName = $originalFile.BaseName -replace '_orig$', ''
        $processedPath = Join-Path -Path $originalFile.DirectoryName -ChildPath ($processedBaseName + $originalFile.Extension)
        if (Test-Path -LiteralPath $processedPath -PathType Leaf) {
            $originalFile
        }
    }
)
$eligibleCount = $eligibleFiles.Count
$deletedCount = 0

Write-Host (Get-LocalizedText -Text '  Folder: {0}' -Arguments @($directory.FullName))
Write-Host (Get-LocalizedText -Text '  Original PDF backups eligible for deletion: {0}' -Arguments @($eligibleCount)) -ForegroundColor Yellow

if ($eligibleCount -eq 0) {
    Write-Host (Get-LocalizedText 'No matching _orig PDFs with a processed PDF were found.') -ForegroundColor Green
    Write-Host ''
    Write-Host (Get-LocalizedText '=== Summary ===') -ForegroundColor Cyan
    Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath))
    Write-Host (Get-LocalizedText 'Found: 0')
    Write-Host (Get-LocalizedText 'Deleted: 0')
    return
}

Write-Host ''
foreach ($originalFile in $eligibleFiles) {
    $relativePath = $originalFile.FullName.Substring($basePathPrefix.Length)
    Write-Host "  - $relativePath"
}

if ($WhatIfPreference) {
    Write-Host ''
    Write-Host (Get-LocalizedText 'Preview: no files were deleted.') -ForegroundColor Cyan
    Write-Host ''
    Write-Host (Get-LocalizedText '=== Summary ===') -ForegroundColor Cyan
    Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath))
    Write-Host (Get-LocalizedText -Text 'Found: {0}' -Arguments @($eligibleCount))
    Write-Host (Get-LocalizedText 'Deleted: 0')
    return
}

$approvedFiles = @(
    foreach ($originalFile in $eligibleFiles) {
        $processedBaseName = $originalFile.BaseName -replace '_orig$', ''
        $processedPath = Join-Path -Path $originalFile.DirectoryName -ChildPath ($processedBaseName + $originalFile.Extension)
        $relativePath = $originalFile.FullName.Substring($basePathPrefix.Length)
        $relativeProcessedPath = $processedPath.Substring($basePathPrefix.Length)
        $action = Get-LocalizedText -Text 'Delete original PDF backup; keep processed PDF: {0}' -Arguments @($relativeProcessedPath)
        if ($PSCmdlet.ShouldProcess($relativePath, $action)) {
            $originalFile
        }
    }
)

if ($approvedFiles.Count -gt 0) {
    Write-Host ''
    Write-Host (Get-LocalizedText 'Deleting original PDF backups...') -ForegroundColor Cyan
}

foreach ($originalFile in $approvedFiles) {
    $relativePath = $originalFile.FullName.Substring($basePathPrefix.Length)
    Remove-Item -LiteralPath $originalFile.FullName -Force
    Write-Host (Get-LocalizedText -Text '  Deleted: {0}' -Arguments @($relativePath)) -ForegroundColor Green
    $deletedCount++
}

Write-Host ''
Write-Host (Get-LocalizedText '=== Summary ===') -ForegroundColor Cyan
Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($summaryPath))
Write-Host (Get-LocalizedText -Text 'Found: {0}' -Arguments @($eligibleCount))
Write-Host (Get-LocalizedText -Text 'Deleted: {0}' -Arguments @($deletedCount))
