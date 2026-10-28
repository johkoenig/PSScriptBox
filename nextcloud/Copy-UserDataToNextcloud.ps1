#Requires -Version 5.1
<#
.SYNOPSIS
    Copies selected Windows user folders into a Nextcloud sync directory.

.DESCRIPTION
    Detects the current user's Desktop, Documents, Pictures, Music, and Videos
    folders and copies selected folders to matching destinations beneath a
    Nextcloud directory. The default Nextcloud path is discovered beneath the
    current user's profile; use -NextcloudPath to specify another location.
    All destination folders must already exist and be writable. Before copying,
    the script checks read access, the user confirms that the Nextcloud sync
    client is paused, and each folder is approved individually. Files with
    matching SHA-256 hashes anywhere in the destination are skipped. Remaining
    files are copied to same-directory .part files, verified, and moved into
    their final names with progress.
    The script never mirrors or deletes unrelated destination content or
    source data. After copying, it reminds the user to enable synchronization
    and wait for completion before running Remove-MigratedUserData.ps1.

    Before starting, the script inventories the selected source and destination
    folders and checks read access. -WhatIf previews actions
    without changing files.

.PARAMETER NextcloudPath
    Existing Nextcloud synchronization directory. If omitted, the
    script uses the current user's 'Nextcloud' profile directory when present,
    otherwise it prompts for a path.

.PARAMETER Folders
    One or more special user folders to copy. Defaults to Desktop,
    Documents, Pictures, Music, and Videos. Pictures are copied to Photos.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.EXAMPLE
    .\Copy-UserDataToNextcloud.ps1 -WhatIf
    Shows which folders would be copied without changing files.

.EXAMPLE
    .\Copy-UserDataToNextcloud.ps1 -NextcloudPath 'D:\Nextcloud' -Folders Documents,Pictures
    Copies the current user's Documents and Pictures folders to Documents and
    Photos beneath D:\Nextcloud.

.NOTES
    Dependencies: Windows PowerShell 5.1 or later. No administrator rights or
    third-party modules are required.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]
param(
    [string] $NextcloudPath,

    [ValidateSet('Desktop', 'Documents', 'Pictures', 'Music', 'Videos')]
    [string[]] $Folders = @('Desktop', 'Documents', 'Pictures', 'Music', 'Videos'),

    [switch] $EnglishOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:OutputLanguage = if (
    $EnglishOutput -or [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'de'
) { 'en' } else { 'de' }
$script:GermanMessages = if ($script:OutputLanguage -eq 'de') {
    Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1')
}
else { @{} }
. (Join-Path $PSScriptRoot '..\common\internal\Get-LocalizedText.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-UserSpecialFolderPaths.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-UserFolders.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-FolderInventory.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-FileSha256.ps1')
. (Join-Path $PSScriptRoot 'internal\Test-FileReadAccess.ps1')
. (Join-Path $PSScriptRoot 'internal\Copy-FileToStaging.ps1')
. (Join-Path $PSScriptRoot 'internal\Copy-ChangedFiles.ps1')

$progressWriter = {
    param([string] $Activity, [string] $Status, [int] $PercentComplete, [switch] $Completed)
    if ($Completed) {
        Write-Progress -Activity $Activity -Completed
    }
    else {
        Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
    }
}

# --- Main program ---------------------------------------------------------

# Document-style banner describing the script's purpose.
$headerLines = @(
    '       .-------------------------------------------.'
    '      /                                           /|'
    '     /___________________________________________/ |'
    '     |  .-------------------------------------.  | |'
    '     |  | COPY USER DATA TO NEXTCLOUD         |  | |'
    '     |  | COPY / VERIFY / PROGRESS            |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)

Write-Host ''
foreach ($headerLine in $headerLines) {
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText '  Copies Windows user folders to a Nextcloud sync folder.') -ForegroundColor Cyan
Write-Host (Get-LocalizedText '  Source files are never deleted.') -ForegroundColor Cyan
Write-Host ''

try {
    Write-Warning (Get-LocalizedText 'Pause the Nextcloud sync client during bulk copy to avoid sync conflicts.')

    # --- Resolve target and source folders -----------------------------------
    if ([string]::IsNullOrWhiteSpace($NextcloudPath)) {
        $profilePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        $defaultPath = if ($profilePath) { Join-Path $profilePath 'Nextcloud' } else { $null }
        if ($defaultPath -and (Test-Path -LiteralPath $defaultPath -PathType Container)) {
            $NextcloudPath = $defaultPath
        }
        else {
            $NextcloudPath = Read-Host -Prompt (Get-LocalizedText 'Enter the Nextcloud synchronization folder path')
        }
    }
    if ([string]::IsNullOrWhiteSpace($NextcloudPath)) {
        throw (Get-LocalizedText 'No Nextcloud path was specified.')
    }
    $NextcloudPath = [Environment]::ExpandEnvironmentVariables($NextcloudPath.Trim().Trim('"'))
    $nextcloudFullPath = [System.IO.Path]::GetFullPath($NextcloudPath)
    if (-not (Test-Path -LiteralPath $nextcloudFullPath -PathType Container)) {
        throw (Get-LocalizedText -Text 'Nextcloud destination does not exist: {0}' -Arguments @($nextcloudFullPath))
    }

    $userFolders = @(Get-UserFolders -Names @($Folders | Select-Object -Unique) -FolderPaths (Get-UserSpecialFolderPaths))
    if ($userFolders.Count -eq 0) {
        Write-Warning (Get-LocalizedText 'No selected Windows user folders were found.')
        return
    }
    Write-Host (Get-LocalizedText '=== Nextcloud copy: processing started ===') -ForegroundColor Cyan
    Write-Host (Get-LocalizedText -Text 'Nextcloud destination: {0}' -Arguments @($nextcloudFullPath))
    Write-Host (Get-LocalizedText -Text 'Number of folders: {0}' -Arguments @($userFolders.Count))
    Write-Host (Get-LocalizedText -Text 'Selected folders: {0}' -Arguments @(($userFolders.Name -join ', ')))

    # --- Plan copies and check read access -----------------------------------
    $results = [System.Collections.Generic.List[object]]::new()
    $migrations = [System.Collections.Generic.List[object]]::new()
    foreach ($folder in $userFolders) {
        $sourcePath = [System.IO.Path]::GetFullPath($folder.SourcePath).TrimEnd('\', '/')
        $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $nextcloudFullPath $folder.TargetName)).TrimEnd('\', '/')
        if ($sourcePath.Equals($destinationPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $results.Add([pscustomobject]@{ Name = $folder.Name; Status = 'Skipped'; Reason = (Get-LocalizedText 'Already at the Nextcloud destination'); Files = 0; Bytes = [long]0 })
            continue
        }
        $sourcePrefix = $sourcePath + [System.IO.Path]::DirectorySeparatorChar
        $destinationPrefix = $destinationPath + [System.IO.Path]::DirectorySeparatorChar
        if ($destinationPath.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
            $sourcePath.StartsWith($destinationPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $results.Add([pscustomobject]@{ Name = $folder.Name; Status = 'Skipped'; Reason = (Get-LocalizedText 'Source and destination overlap'); Files = 0; Bytes = [long]0 })
            continue
        }
        $migrations.Add([pscustomobject]@{
            Folder = $folder
            SourcePath = $sourcePath
            DestinationPath = $destinationPath
            SourceInventory = $null
            DestinationInventory = $null
        })
    }

    # Verify read access before any folder is copied.
    $accessProblems = [System.Collections.Generic.List[object]]::new()
    foreach ($migration in $migrations) {
        Write-Host (Get-LocalizedText -Text 'Checking source folder: {0}' -Arguments @($migration.SourcePath))
        try {
            $migration.SourceInventory = Get-FolderInventory -Path $migration.SourcePath
        }
        catch {
            $accessProblems.Add([pscustomobject]@{
                Path = $migration.SourcePath
                Reason = (Get-LocalizedText -Text 'Folder cannot be read: {0}' -Arguments @($_.Exception.Message))
            })
        }
        if (-not (Test-Path -LiteralPath $migration.DestinationPath -PathType Container)) {
            $accessProblems.Add([pscustomobject]@{
                Path = $migration.DestinationPath
                Reason = Get-LocalizedText 'Destination folder does not exist'
            })
            continue
        }
        Write-Host (Get-LocalizedText -Text 'Checking destination folder: {0}' -Arguments @($migration.DestinationPath))
        try {
            $migration.DestinationInventory = Get-FolderInventory -Path $migration.DestinationPath
        }
        catch {
            $accessProblems.Add([pscustomobject]@{
                Path = $migration.DestinationPath
                Reason = (Get-LocalizedText -Text 'Folder cannot be read: {0}' -Arguments @($_.Exception.Message))
            })
        }
        if ($null -eq $migration.SourceInventory -or $null -eq $migration.DestinationInventory) {
            continue
        }
        foreach ($file in $migration.SourceInventory.Files) {
            $filePath = Join-Path $migration.SourcePath $file.RelativePath
            foreach ($problem in @(Test-FileReadAccess -Path $filePath -Language $script:OutputLanguage -Messages $script:GermanMessages)) {
                $accessProblems.Add($problem)
            }
        }
        foreach ($file in $migration.DestinationInventory.Files) {
            $filePath = Join-Path $migration.DestinationPath $file.RelativePath
            foreach ($problem in @(Test-FileReadAccess -Path $filePath -Language $script:OutputLanguage -Messages $script:GermanMessages)) {
                $accessProblems.Add($problem)
            }
        }
    }
    if ($accessProblems.Count -gt 0) {
        $maxListed = 50
        Write-Host ''
        Write-Host (Get-LocalizedText -Text 'Read access problems for {0} item(s):' -Arguments @($accessProblems.Count)) -ForegroundColor Cyan
        foreach ($problem in ($accessProblems | Select-Object -First $maxListed)) {
            Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($problem.Path, $problem.Reason)) -ForegroundColor Yellow
        }
        if ($accessProblems.Count -gt $maxListed) {
            Write-Host (Get-LocalizedText -Text '  ... and {0} more' -Arguments @($accessProblems.Count - $maxListed)) -ForegroundColor Yellow
        }
        Write-Host ''
        Write-Host (Get-LocalizedText 'Copy not started: fix the read access problems listed above or exclude the affected folders with -Folders.') -ForegroundColor Red
        exit 1
    }

    # The client must be paused to prevent a concurrent sync from changing files.
    $syncPaused = $true
    if (-not $WhatIfPreference -and $migrations.Count -gt 0) {
        Write-Host ''
        Write-Host (Get-LocalizedText '=== Confirm the Nextcloud sync client is paused ===') -ForegroundColor Cyan
        $answer = (Read-Host -Prompt (Get-LocalizedText 'Confirm the Nextcloud sync client is paused. Continue? [y/N]')).Trim()
        $syncPaused = $answer -match '^(?i:y|yes|j|ja)$'
        if (-not $syncPaused) {
            Write-Host (Get-LocalizedText 'Copy cancelled; no folders were changed.') -ForegroundColor Yellow
        }
    }

    # --- Copy and verify each selected folder --------------------------------
    for ($i = 0; $syncPaused -and $i -lt $migrations.Count; $i++) {
        $migration = $migrations[$i]
        $folder = $migration.Folder
        $sourcePath = $migration.SourcePath
        $destinationPath = $migration.DestinationPath
        $result = [pscustomobject]@{ Name = $folder.Name; Status = 'Failed'; Reason = ''; Files = 0; Bytes = [long]0 }
        $results.Add($result)
        Write-Host ''
        Write-Host (Get-LocalizedText -Text '--- Folder {0}/{1}: {2} ---' -Arguments @(($i + 1), $migrations.Count, $folder.Name)) -ForegroundColor Cyan
        try {
            $sourceInventory = $migration.SourceInventory
            Write-Host (Get-LocalizedText -Text 'Selected {0}: {1} files, {2:N2} MB' -Arguments @(
                $folder.Name, $sourceInventory.Files.Count, ($sourceInventory.TotalBytes / 1MB)
            ))
            $sizeMb = $sourceInventory.TotalBytes / 1MB
            $copyAction = Get-LocalizedText -Text 'Copy folder from {0} ({1:N2} MB)' -Arguments @($sourcePath, $sizeMb)
            $copyApproved = $false
            if ($WhatIfPreference -or ($PSBoundParameters.ContainsKey('Confirm') -and $Confirm)) {
                $copyApproved = $PSCmdlet.ShouldProcess($destinationPath, $copyAction)
            }
            else {
                $prompt = Get-LocalizedText -Text 'Copy folder {0} ({1:N2} MB)? [y/N]' -Arguments @($folder.Name, $sizeMb)
                $answer = (Read-Host -Prompt $prompt).Trim()
                if ($answer -match '^(?i:y|yes|j|ja)$') {
                    $copyApproved = $PSCmdlet.ShouldProcess($destinationPath, $copyAction)
                }
            }
            if (-not $copyApproved) {
                $result.Status = 'Skipped'
                $result.Reason = Get-LocalizedText 'Not performed (preview or declined)'
                continue
            }

            $copyResult = Copy-ChangedFiles -Source $sourcePath -Destination $destinationPath `
                -SourceInventory $sourceInventory -DestinationInventory $migration.DestinationInventory `
                -FolderName $folder.Name -Language $script:OutputLanguage -Messages $script:GermanMessages `
                -ProgressReporter $progressWriter
            Write-Host (Get-LocalizedText -Text 'Copied folder verified: {0}' -Arguments @($folder.Name)) -ForegroundColor Green
            $result.Status = 'Success'
            Write-Host (Get-LocalizedText -Text 'Copied: {0} files; matching content was already in the destination for {1} files.' -Arguments @(
                $copyResult.CopiedFiles, $copyResult.IdenticalFiles
            ))
            $result.Files = $copyResult.CopiedFiles
            $result.Bytes = [long]$copyResult.CopiedBytes

        }
        catch {
            $result.Status = 'Failed'
            $result.Reason = $_.Exception.Message
            Write-Warning (Get-LocalizedText -Text 'Error for ''{0}'': {1}' -Arguments @($folder.Name, $_.Exception.Message))
        }
    }

    # --- Summary ---------------------------------------------------------------
    $successResults = @($results | Where-Object { $_.Status -eq 'Success' })
    $skippedResults = @($results | Where-Object { $_.Status -eq 'Skipped' })
    $failedResults = @($results | Where-Object { $_.Status -eq 'Failed' })
    $copiedFiles = [long](($successResults | ForEach-Object { [long]$_.Files }) | Measure-Object -Sum).Sum
    $copiedBytes = [long](($successResults | ForEach-Object { [long]$_.Bytes }) | Measure-Object -Sum).Sum
    if (-not $syncPaused) {
        foreach ($migration in $migrations) {
            $results.Add([pscustomobject]@{
                Name = $migration.Folder.Name
                Status = 'Skipped'
                Reason = Get-LocalizedText 'Copy cancelled; sync client was not confirmed paused'
                Files = 0
                Bytes = [long]0
            })
        }
        $skippedResults = @($results | Where-Object { $_.Status -eq 'Skipped' })
    }

    Write-Host ''
    Write-Host (Get-LocalizedText '=== Summary ===') -ForegroundColor Cyan
    Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($nextcloudFullPath))
    Write-Host (Get-LocalizedText -Text 'Succeeded: {0}, skipped: {1}, failed: {2}' -Arguments @($successResults.Count, $skippedResults.Count, $failedResults.Count))
    if ($successResults.Count -gt 0) {
        Write-Host (Get-LocalizedText -Text 'Copied total: {0} files, {1:N2} MB' -Arguments @($copiedFiles, ($copiedBytes / 1MB)))
    }
    Write-Host ''
    Write-Host (Get-LocalizedText 'Failed folders:') -ForegroundColor Cyan
    if ($failedResults.Count -eq 0) {
        Write-Host (Get-LocalizedText '  None.')
    }
    else {
        foreach ($failedResult in $failedResults) {
            Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($failedResult.Name, $failedResult.Reason)) -ForegroundColor Yellow
        }
    }
    Write-Host ''
    Write-Host (Get-LocalizedText 'Skipped folders:') -ForegroundColor Cyan
    if ($skippedResults.Count -eq 0) {
        Write-Host (Get-LocalizedText '  None.')
    }
    else {
        foreach ($skippedResult in $skippedResults) {
            Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($skippedResult.Name, $skippedResult.Reason)) -ForegroundColor Yellow
        }
    }
    if (-not $WhatIfPreference -and $syncPaused) {
        Write-Host ''
        Write-Host (Get-LocalizedText 'Copy finished. Enable the Nextcloud sync client and wait until synchronization completes before running Remove-MigratedUserData.ps1.') -ForegroundColor Cyan
    }
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
