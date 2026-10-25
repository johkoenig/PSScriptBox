#Requires -Version 5.1
<#
.SYNOPSIS
    Removes matching local files and empty subfolders represented in Nextcloud.

.DESCRIPTION
    Finds the current user's Desktop, Documents, Pictures, Music, and Videos
    folders and compares each selected local file's SHA-256 hash with files
    beneath its corresponding Nextcloud folder. Before deleting anything, the
    user confirms that synchronization to the server has fully completed.
    The script then shows the number and total size of matching local files,
    counts subfolders that also exist in Nextcloud, and requests approval
    separately for each main folder. Matching local files are deleted after
    their hashes are rechecked. Empty local subfolders are also deleted only
    when the corresponding Nextcloud folder exists; non-matching files and the
    selected main folders are retained.

    The Nextcloud client must have completed synchronization before this
    script runs. The script can compare local files but cannot independently
    verify the server state. -WhatIf previews deletion without changing files.

.PARAMETER NextcloudPath
    Existing Nextcloud synchronization directory. If omitted, the script uses
    the current user's 'Nextcloud' profile directory when present; otherwise
    it prompts for a path.

.PARAMETER Folders
    One or more special user folders to inspect. Defaults to Desktop,
    Documents, Pictures, Music, and Videos. Pictures map to Photos.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.EXAMPLE
    .\Remove-MigratedUserData.ps1 -WhatIf
    Shows matching local files and corresponding subfolders that may be removed.

.EXAMPLE
    .\Remove-MigratedUserData.ps1 -NextcloudPath 'D:\Nextcloud' -Folders Documents,Pictures
    Checks and interactively removes matching local Documents and Pictures
    files after the user confirms that synchronization has completed.

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
$script:ExcludedNames = @(
    '$RECYCLE.BIN',
    'desktop.ini',
    'Thumbs.db',
    'System Volume Information'
)

<#
.SYNOPSIS
    Returns a localized console message.

.DESCRIPTION
    Selects German text when German output is active and otherwise uses the
    English source message. Formats the selected text when arguments are given.

.PARAMETER Text
    English source message and localization key.

.PARAMETER Arguments
    Values for formatting placeholders in the message.

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

<#
.SYNOPSIS
    Resolves selected Windows special user folders.

.DESCRIPTION
    Uses Windows-known folder locations so redirected folders and localized
    profile layouts are discovered from the current user's operating system.

.PARAMETER Names
    Special user folder names requested for inspection.

.OUTPUTS
    PSCustomObject[] with source Name, SourcePath, and target TargetName.
#>
function Get-UserFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]] $Names
    )

    $specialFolderNames = @{
        Desktop   = 'DesktopDirectory'
        Documents = 'MyDocuments'
        Pictures  = 'MyPictures'
        Music     = 'MyMusic'
        Videos    = 'MyVideos'
    }
    foreach ($name in $Names) {
        $specialFolder = [System.Enum]::Parse([System.Environment+SpecialFolder], $specialFolderNames[$name])
        $sourcePath = [Environment]::GetFolderPath($specialFolder)
        if ([string]::IsNullOrWhiteSpace($sourcePath) -or
            -not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
            Write-Warning (Get-LocalizedText -Text 'The Windows folder could not be found and will be skipped: {0}' -Arguments @($name))
            continue
        }
        [pscustomobject]@{
            Name       = $name
            SourcePath = [System.IO.Path]::GetFullPath($sourcePath)
            TargetName = if ($name -eq 'Pictures') { 'Photos' } else { $name }
        }
    }
}

<#
.SYNOPSIS
    Inventories files beneath a folder.

.DESCRIPTION
    Produces a relative-path inventory while excluding configured system
    artifacts and links (symbolic links, junctions). Nextcloud virtual files
    and folders are reparse points without a link type; they are included, so
    their content can be hashed. Enumeration errors terminate the inventory.

.PARAMETER Path
    Existing folder to inventory.

.OUTPUTS
    PSCustomObject with Files, Directories, ReparsePoints, and TotalBytes.
#>
function Get-FolderInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Path
    )

    $root = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $prefix = $root + [System.IO.Path]::DirectorySeparatorChar
    $files = [System.Collections.Generic.List[object]]::new()
    $directories = [System.Collections.Generic.List[string]]::new()
    $reparsePoints = [System.Collections.Generic.List[object]]::new()
    $totalBytes = [long]0
    $pendingDirectories = [System.Collections.Generic.Stack[string]]::new()
    $pendingDirectories.Push($root)
    while ($pendingDirectories.Count -gt 0) {
        $currentDirectory = $pendingDirectories.Pop()
        foreach ($item in Get-ChildItem -LiteralPath $currentDirectory -Force -ErrorAction Stop) {
            if ($script:ExcludedNames -contains $item.Name) { continue }
            $relativePath = $item.FullName.Substring($prefix.Length)
            # Skip links to avoid leaving the tree or looping; placeholders have no LinkType.
            if (-not [string]::IsNullOrEmpty([string]$item.LinkType)) {
                $reparsePoints.Add([pscustomobject]@{
                    RelativePath = $relativePath
                    IsDirectory  = [bool]$item.PSIsContainer
                })
                continue
            }
            if ($item.PSIsContainer) {
                $directories.Add($relativePath)
                $pendingDirectories.Push($item.FullName)
            }
            else {
                $files.Add([pscustomobject]@{
                    RelativePath = $relativePath
                    Length       = [long]$item.Length
                })
                $totalBytes += [long]$item.Length
            }
        }
    }
    [pscustomobject]@{
        Files         = @($files.ToArray())
        Directories   = @($directories.ToArray())
        ReparsePoints = @($reparsePoints.ToArray())
        TotalBytes    = $totalBytes
    }
}

<#
.SYNOPSIS
    Computes the SHA-256 hash of a file.

.DESCRIPTION
    Reads the file through a .NET stream instead of Get-FileHash. Get-FileHash
    returns no Hash property under -WhatIf in Windows PowerShell 5.1, so
    previews could not compare contents. Hashing is read-only and runs in
    previews as well.

.PARAMETER Path
    Existing file to hash.

.OUTPUTS
    System.String. The uppercase hexadecimal SHA-256 hash, matching Get-FileHash.
#>
function Get-FileSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($fullPath)
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($stream)) -replace '-', '')
    }
    finally {
        $stream.Dispose()
        $sha256.Dispose()
    }
}

<#
.SYNOPSIS
    Removes empty local subfolders with an existing Nextcloud counterpart.

.DESCRIPTION
    Checks subfolders in descending path length so nested empty folders are
    removed first. Links are not traversed, and non-empty folders are never
    deleted recursively.

.PARAMETER SourcePath
    Local main folder.

.PARAMETER DestinationPath
    Corresponding Nextcloud main folder.

.PARAMETER RelativeDirectories
    Relative paths of subfolders found in both inventories.

.OUTPUTS
    PSCustomObject with the deleted-folder count and failed paths.
#>
function Remove-EmptyMatchingDirectories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $SourcePath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $DestinationPath,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $RelativeDirectories
    )

    $deletedCount = 0
    $failedDirectories = [System.Collections.Generic.List[string]]::new()
    foreach ($relativeDirectory in ($RelativeDirectories | Sort-Object { $_.Length } -Descending)) {
        $sourceDirectoryPath = Join-Path $SourcePath $relativeDirectory
        $destinationDirectoryPath = Join-Path $DestinationPath $relativeDirectory
        try {
            if (-not (Test-Path -LiteralPath $sourceDirectoryPath -PathType Container) -or
                -not (Test-Path -LiteralPath $destinationDirectoryPath -PathType Container)) {
                continue
            }
            $sourceDirectory = Get-Item -LiteralPath $sourceDirectoryPath -Force -ErrorAction Stop
            $destinationDirectory = Get-Item -LiteralPath $destinationDirectoryPath -Force -ErrorAction Stop
            if (-not [string]::IsNullOrEmpty([string]$sourceDirectory.LinkType) -or
                -not [string]::IsNullOrEmpty([string]$destinationDirectory.LinkType)) {
                continue
            }
            $entries = [System.IO.Directory]::GetFileSystemEntries($sourceDirectoryPath)
            if ($entries.Length -eq 0) {
                Remove-Item -LiteralPath $sourceDirectoryPath -Force -ErrorAction Stop
                $deletedCount++
            }
        }
        catch {
            $failedDirectories.Add($relativeDirectory)
            Write-Warning (Get-LocalizedText -Text 'Could not delete local folder ''{0}'': {1}' -Arguments @(
                $relativeDirectory, $_.Exception.Message
            ))
        }
    }
    [pscustomobject]@{
        DeletedCount = $deletedCount
        FailedDirectories = @($failedDirectories.ToArray())
    }
}

# --- Banner ---------------------------------------------------------------
$headerLines = @(
    '       .-------------------------------------------.'
    '      /                                           /|'
    '     /___________________________________________/ |'
    '     |  .-------------------------------------.  | |'
    '     |  | NEXTCLOUD LOCAL CLEANUP             |  | |'
    '     |  | HASH CHECK / CONFIRM / REMOVE       |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)

Write-Host ''
foreach ($headerLine in $headerLines) {
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText '  Removes local files and empty subfolders when they exist in Nextcloud.') -ForegroundColor Cyan
Write-Host (Get-LocalizedText '  Files and folders are removed only after synchronization and per-folder approval.') -ForegroundColor Cyan
Write-Host ''

try {
    # --- Resolve paths and folders -----------------------------------------
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

    $userFolders = @(Get-UserFolders -Names @($Folders | Select-Object -Unique))
    if ($userFolders.Count -eq 0) {
        Write-Warning (Get-LocalizedText 'No selected Windows user folders were found.')
        return
    }
    Write-Host (Get-LocalizedText '=== Nextcloud local cleanup: processing started ===') -ForegroundColor Cyan
    Write-Host (Get-LocalizedText -Text 'Nextcloud destination: {0}' -Arguments @($nextcloudFullPath))
    Write-Host (Get-LocalizedText -Text 'Number of folders: {0}' -Arguments @($userFolders.Count))
    Write-Host (Get-LocalizedText -Text 'Selected folders: {0}' -Arguments @(($userFolders.Name -join ', ')))

    # --- Build the deletion plan --------------------------------------------
    $plans = [System.Collections.Generic.List[object]]::new()
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($folder in $userFolders) {
        $sourcePath = [System.IO.Path]::GetFullPath($folder.SourcePath).TrimEnd('\', '/')
        $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $nextcloudFullPath $folder.TargetName)).TrimEnd('\', '/')
        $sourcePrefix = $sourcePath + [System.IO.Path]::DirectorySeparatorChar
        $destinationPrefix = $destinationPath + [System.IO.Path]::DirectorySeparatorChar
        if ($sourcePath.Equals($destinationPath, [System.StringComparison]::OrdinalIgnoreCase) -or
            $destinationPath.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
            $sourcePath.StartsWith($destinationPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $results.Add([pscustomobject]@{
                Name = $folder.Name
                Status = 'Skipped'
                Reason = Get-LocalizedText 'Source and Nextcloud destination overlap'
                Files = 0
                Bytes = [long]0
            })
            continue
        }
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
            throw (Get-LocalizedText -Text 'Destination folder does not exist: {0}' -Arguments @($destinationPath))
        }

        $sourceInventory = Get-FolderInventory -Path $sourcePath
        $destinationInventory = Get-FolderInventory -Path $destinationPath
        $destinationDirectories = @{}
        foreach ($relativeDirectory in $destinationInventory.Directories) {
            $destinationDirectories[$relativeDirectory] = $true
        }
        $matchingDirectories = [System.Collections.Generic.List[string]]::new()
        foreach ($relativeDirectory in $sourceInventory.Directories) {
            if ($destinationDirectories.ContainsKey($relativeDirectory)) {
                $matchingDirectories.Add($relativeDirectory)
            }
        }
        $sourceSizes = @{}
        foreach ($file in $sourceInventory.Files) { $sourceSizes[[long]$file.Length] = $true }
        $destinationHashes = @{}
        foreach ($file in $destinationInventory.Files) {
            if (-not $sourceSizes.ContainsKey([long]$file.Length)) { continue }
            $destinationFilePath = Join-Path $destinationPath $file.RelativePath
            $hash = Get-FileSha256 -Path $destinationFilePath
            if (-not $destinationHashes.ContainsKey($hash)) {
                $destinationHashes[$hash] = [System.Collections.Generic.List[string]]::new()
            }
            $destinationHashes[$hash].Add($destinationFilePath)
        }

        $matches = [System.Collections.Generic.List[object]]::new()
        $totalBytes = [long]0
        if ($destinationHashes.Count -gt 0) {
            foreach ($file in $sourceInventory.Files) {
                $sourceFilePath = Join-Path $sourcePath $file.RelativePath
                $sourceHash = Get-FileSha256 -Path $sourceFilePath
                if ($destinationHashes.ContainsKey($sourceHash)) {
                    $matches.Add([pscustomobject]@{
                        RelativePath = $file.RelativePath
                        Length = [long]$file.Length
                        Hash = $sourceHash
                        DestinationPaths = @($destinationHashes[$sourceHash].ToArray())
                    })
                    $totalBytes += [long]$file.Length
                }
            }
        }
        $plans.Add([pscustomobject]@{
            Folder = $folder
            SourcePath = $sourcePath
            DestinationPath = $destinationPath
            Matches = @($matches.ToArray())
            MatchingDirectories = @($matchingDirectories.ToArray())
            TotalBytes = $totalBytes
        })
    }

    # --- Present overview and require completed synchronization -------------
    for ($i = 0; $i -lt $plans.Count; $i++) {
        $plan = $plans[$i]
        Write-Host ''
        Write-Host (Get-LocalizedText -Text '--- Folder {0}/{1}: {2} ---' -Arguments @(($i + 1), $plans.Count, $plan.Folder.Name)) -ForegroundColor Cyan
        Write-Host (Get-LocalizedText -Text 'Matching local files: {0} ({1:N2} MB)' -Arguments @(
            $plan.Matches.Count, ($plan.TotalBytes / 1MB)
        ))
        Write-Host (Get-LocalizedText -Text 'Local subfolders with a matching Nextcloud folder: {0}' -Arguments @(
            $plan.MatchingDirectories.Count
        ))
    }

    $syncCompleted = $true
    $plannedCleanupCount = 0
    foreach ($plan in $plans) {
        $plannedCleanupCount += $plan.Matches.Count + $plan.MatchingDirectories.Count
    }
    if (-not $WhatIfPreference -and $plannedCleanupCount -gt 0) {
        $answer = (Read-Host -Prompt (Get-LocalizedText 'Confirm Nextcloud synchronization to the server has fully completed. Continue? [y/N]')).Trim()
        $syncCompleted = $answer -match '^(?i:y|yes|j|ja)$'
        if (-not $syncCompleted) {
            Write-Host (Get-LocalizedText 'Deletion cancelled; no local files were removed.') -ForegroundColor Yellow
        }
    }

    # --- Confirm and remove matching files per main folder ------------------
    for ($i = 0; $syncCompleted -and $i -lt $plans.Count; $i++) {
        $plan = $plans[$i]
        if ($plan.Matches.Count -eq 0 -and $plan.MatchingDirectories.Count -eq 0) {
            $results.Add([pscustomobject]@{
                Name = $plan.Folder.Name
                Status = 'Skipped'
                Reason = Get-LocalizedText 'No matching local files or subfolders were found in Nextcloud'
                Files = 0
                Directories = 0
                Bytes = [long]0
            })
            continue
        }

        Write-Host ''
        Write-Host (Get-LocalizedText -Text '--- Folder {0}/{1}: {2} ---' -Arguments @(($i + 1), $plans.Count, $plan.Folder.Name)) -ForegroundColor Cyan
        $prompt = Get-LocalizedText -Text 'Delete {0} local files ({1:N2} MB) and check {2} matching subfolders in {3}? [y/N]' -Arguments @(
            $plan.Matches.Count, ($plan.TotalBytes / 1MB), $plan.MatchingDirectories.Count, $plan.Folder.Name
        )
        $action = Get-LocalizedText -Text 'Remove {0} local files ({1:N2} MB) and empty subfolders with matching Nextcloud folders' -Arguments @(
            $plan.Matches.Count, ($plan.TotalBytes / 1MB)
        )
        $approved = $false
        if ($WhatIfPreference -or ($PSBoundParameters.ContainsKey('Confirm') -and $Confirm)) {
            $approved = $PSCmdlet.ShouldProcess($plan.SourcePath, $action)
        }
        else {
            $answer = (Read-Host -Prompt $prompt).Trim()
            if ($answer -match '^(?i:y|yes|j|ja)$') {
                $approved = $PSCmdlet.ShouldProcess($plan.SourcePath, $action)
            }
        }
        if (-not $approved) {
            $results.Add([pscustomobject]@{
                Name = $plan.Folder.Name
                Status = 'Skipped'
                Reason = Get-LocalizedText 'Not performed (preview or declined)'
                Files = 0
                Directories = 0
                Bytes = [long]0
            })
            continue
        }

        $deletedFiles = 0
        $deletedBytes = [long]0
        $failedFiles = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $plan.Matches) {
            $sourceFilePath = Join-Path $plan.SourcePath $file.RelativePath
            try {
                if (-not (Test-Path -LiteralPath $sourceFilePath -PathType Leaf)) {
                    throw (Get-LocalizedText -Text 'Local file changed before deletion: {0}' -Arguments @($file.RelativePath))
                }
                $sourceHash = Get-FileSha256 -Path $sourceFilePath
                $destinationStillMatches = $false
                foreach ($destinationFilePath in $file.DestinationPaths) {
                    if (-not (Test-Path -LiteralPath $destinationFilePath -PathType Leaf)) { continue }
                    $destinationHash = Get-FileSha256 -Path $destinationFilePath
                    if ($sourceHash -eq $destinationHash -and $sourceHash -eq $file.Hash) {
                        $destinationStillMatches = $true
                        break
                    }
                }
                if (-not $destinationStillMatches) {
                    throw (Get-LocalizedText -Text 'No identical Nextcloud file remains; local file retained: {0}' -Arguments @($file.RelativePath))
                }
                Remove-Item -LiteralPath $sourceFilePath -Force -ErrorAction Stop
                $deletedFiles++
                $deletedBytes += [long]$file.Length
            }
            catch {
                $failedFiles.Add($file.RelativePath)
                Write-Warning (Get-LocalizedText -Text 'Could not delete local file ''{0}'': {1}' -Arguments @(
                    $file.RelativePath, $_.Exception.Message
                ))
            }
        }
        $directoryResult = Remove-EmptyMatchingDirectories `
            -SourcePath $plan.SourcePath -DestinationPath $plan.DestinationPath `
            -RelativeDirectories $plan.MatchingDirectories
        $deletedDirectories = $directoryResult.DeletedCount
        $failedDirectories = $directoryResult.FailedDirectories
        $results.Add([pscustomobject]@{
            Name = $plan.Folder.Name
            Status = if ($failedFiles.Count -gt 0 -or $failedDirectories.Count -gt 0) { 'Failed' } else { 'Success' }
            Reason = if ($failedFiles.Count -gt 0 -or $failedDirectories.Count -gt 0) {
                Get-LocalizedText -Text '{0} local file(s) and {1} local folder(s) could not be removed.' -Arguments @(
                    $failedFiles.Count, $failedDirectories.Count
                )
            } else { '' }
            Files = $deletedFiles
            Directories = $deletedDirectories
            Bytes = $deletedBytes
        })
        Write-Host (Get-LocalizedText -Text 'Deleted locally: {0} files ({1:N2} MB).' -Arguments @(
            $deletedFiles, ($deletedBytes / 1MB)
        )) -ForegroundColor Green
        Write-Host (Get-LocalizedText -Text 'Deleted locally: {0} empty subfolders.' -Arguments @(
            $deletedDirectories
        )) -ForegroundColor Green
    }

    if (-not $syncCompleted) {
        foreach ($plan in $plans) {
            if ($plan.Matches.Count -eq 0 -and $plan.MatchingDirectories.Count -eq 0) {
                $results.Add([pscustomobject]@{
                    Name = $plan.Folder.Name
                    Status = 'Skipped'
                    Reason = Get-LocalizedText 'No matching local files or subfolders were found in Nextcloud'
                    Files = 0
                    Directories = 0
                    Bytes = [long]0
                })
                continue
            }
            $results.Add([pscustomobject]@{
                Name = $plan.Folder.Name
                Status = 'Skipped'
                Reason = Get-LocalizedText 'Synchronization was not confirmed complete'
                Files = 0
                Directories = 0
                Bytes = [long]0
            })
        }
    }

    # --- Summary ------------------------------------------------------------
    $successResults = @($results | Where-Object { $_.Status -eq 'Success' })
    $skippedResults = @($results | Where-Object { $_.Status -eq 'Skipped' })
    $failedResults = @($results | Where-Object { $_.Status -eq 'Failed' })
    $deletedFilesTotal = [long](($successResults | ForEach-Object { [long]$_.Files }) | Measure-Object -Sum).Sum
    $deletedBytesTotal = [long](($successResults | ForEach-Object { [long]$_.Bytes }) | Measure-Object -Sum).Sum
    $deletedDirectoriesTotal = [long](($successResults | ForEach-Object { [long]$_.Directories }) | Measure-Object -Sum).Sum
    Write-Host ''
    Write-Host (Get-LocalizedText '=== Summary ===') -ForegroundColor Cyan
    Write-Host (Get-LocalizedText -Text 'Path: {0}' -Arguments @($nextcloudFullPath))
    Write-Host (Get-LocalizedText -Text 'Succeeded: {0}, skipped: {1}, failed: {2}' -Arguments @(
        $successResults.Count, $skippedResults.Count, $failedResults.Count
    ))
    Write-Host (Get-LocalizedText -Text 'Deleted total: {0} local files ({1:N2} MB).' -Arguments @(
        $deletedFilesTotal, ($deletedBytesTotal / 1MB)
    ))
    Write-Host (Get-LocalizedText -Text 'Deleted total: {0} empty local subfolders.' -Arguments @(
        $deletedDirectoriesTotal
    ))
    Write-Host ''
    Write-Host (Get-LocalizedText 'Failed folders:') -ForegroundColor Cyan
    if ($failedResults.Count -eq 0) {
        Write-Host (Get-LocalizedText '  None.')
    }
    else {
        foreach ($result in $failedResults) {
            Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($result.Name, $result.Reason)) -ForegroundColor Yellow
        }
    }
    Write-Host ''
    Write-Host (Get-LocalizedText 'Skipped folders:') -ForegroundColor Cyan
    if ($skippedResults.Count -eq 0) {
        Write-Host (Get-LocalizedText '  None.')
    }
    else {
        foreach ($result in $skippedResults) {
            Write-Host (Get-LocalizedText -Text '  - {0} ({1})' -Arguments @($result.Name, $result.Reason)) -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
