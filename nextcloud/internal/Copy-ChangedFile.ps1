<#
.SYNOPSIS
    Provides the changed-file copy helper for the Nextcloud scripts.

.DESCRIPTION
    Defines Copy-ChangedFile. Requires Get-LocalizedText.ps1, Get-FileSha256.ps1,
    and Copy-FileToStaging.ps1 from the same folder.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Copies non-identical files and verifies destination content.

.DESCRIPTION
    Skips a source file when any file in the destination has the same SHA-256
    hash, and also skips a source file whose content is already planned for
    copying from an earlier source file. Copies other files through same-folder
    staging files with a .part extension and verifies their hashes before
    publishing. Creates missing destination folders.
    When supplied, progress is passed to the ProgressReporter callback instead
    of being written to the console. Without a callback, no progress is reported.

.PARAMETER Source
    Source folder.

.PARAMETER Destination
    Existing destination folder.

.PARAMETER SourceInventory
    Inventory captured before copying (Files, Directories, TotalBytes).

.PARAMETER DestinationInventory
    Inventory captured before copying (Files).

.PARAMETER FolderName
    Display name of the selected user folder, used in progress and errors.

.PARAMETER Language
    'de' selects German messages; any other value selects English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.PARAMETER ProgressReporter
    Optional callback invoked with -Activity, -Status, and -PercentComplete
    while checking and copying, and with -Activity -Completed at the end.
    Without a callback, no progress is reported.

.OUTPUTS
    PSCustomObject with CopiedFiles, IdenticalFiles, and CopiedBytes.

.NOTES
    Throws when a source file changes during the identical-content check or when
    a staged file does not match its expected hash before publication.
#>
function Copy-ChangedFile
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Destination,
        [Parameter(Mandatory)][psobject] $SourceInventory,
        [Parameter(Mandatory)][psobject] $DestinationInventory,
        [Parameter(Mandatory)][string] $FolderName,
        [string] $Language = 'en',
        [string]$MessagesPath = '',
        [AllowNull()][scriptblock] $ProgressReporter
    )

    $sourceSizes = @{}
    foreach ($file in $SourceInventory.Files) {
        $sourceSizes[[long]$file.Length] = $true
    }
    $destinationHashes = @{}
    foreach ($file in $DestinationInventory.Files) {
        if (-not $sourceSizes.ContainsKey([long]$file.Length)) { continue }
        $destinationFilePath = Join-Path $Destination $file.RelativePath
        $hash = Get-FileSha256 -Path $destinationFilePath
        if (-not $destinationHashes.ContainsKey($hash)) {
            $destinationHashes[$hash] = [System.Collections.Generic.List[string]]::new()
        }
        $destinationHashes[$hash].Add($destinationFilePath)
    }

    $copiedFiles = 0
    $identicalFiles = 0
    $copiedBytes = [long]0
    $identicalBytes = [long]0
    $copyPlan = [System.Collections.Generic.List[object]]::new()
    $plannedHashes = @{}
    foreach ($relativeDirectory in ($SourceInventory.Directories | Sort-Object { $_.Length })) {
        [System.IO.Directory]::CreateDirectory((Join-Path $Destination $relativeDirectory)) | Out-Null
    }
    $activity = Get-LocalizedText -Text 'Copying folder {0}' -Arguments @($FolderName) -Language $Language -MessagesPath $MessagesPath
    for ($i = 0; $i -lt $SourceInventory.Files.Count; $i++) {
        $file = $SourceInventory.Files[$i]
        if ($SourceInventory.Files.Count -gt 0 -and $null -ne $ProgressReporter)
        {
            $checkPercent = [int](100 * $i / $SourceInventory.Files.Count)
            & $ProgressReporter -Activity $activity `
                -Status (Get-LocalizedText -Text 'Checking files for identical content' -Language $Language -MessagesPath $MessagesPath) `
                -PercentComplete $checkPercent
        }
        $sourceFilePath = Join-Path $Source $file.RelativePath
        $sourceHash = Get-FileSha256 -Path $sourceFilePath
        $alreadyPresent = $false
        if ($destinationHashes.ContainsKey($sourceHash)) {
            foreach ($candidatePath in $destinationHashes[$sourceHash]) {
                if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { continue }
                $candidateHash = Get-FileSha256 -Path $candidatePath
                if ($sourceHash -eq $candidateHash) {
                    $alreadyPresent = $true
                    break
                }
            }
        }
        if (-not $alreadyPresent -and $plannedHashes.ContainsKey($sourceHash)) {
            $alreadyPresent = $true
        }
        if ($alreadyPresent) {
            $sourceHashAfterCheck = Get-FileSha256 -Path $sourceFilePath
            if ($sourceHashAfterCheck -ne $sourceHash) {
                throw (Get-LocalizedText -Text 'Source file changed while checking for identical content: {0}' `
                        -Arguments @($file.RelativePath) -Language $Language -MessagesPath $MessagesPath)
            }
            $identicalFiles++
            $identicalBytes += [long]$file.Length
            continue
        }
        $plannedHashes[$sourceHash] = $true
        $copyPlan.Add([pscustomobject]@{ File = $file; Hash = $sourceHash })
    }

    $completedBytes = $identicalBytes
    foreach ($copyItem in $copyPlan) {
        $file = $copyItem.File
        $sourceFilePath = Join-Path $Source $file.RelativePath
        $destinationFilePath = Join-Path $Destination $file.RelativePath
        $sourceFileDirectory = [System.IO.Path]::GetDirectoryName($sourceFilePath)
        $sourceFileName = [System.IO.Path]::GetFileName($sourceFilePath)
        $destinationFileDirectory = [System.IO.Path]::GetDirectoryName($destinationFilePath)
        Copy-FileToStaging -SourceDirectory $sourceFileDirectory `
            -DestinationDirectory $destinationFileDirectory -FileName $sourceFileName `
            -RelativePath $file.RelativePath -FileLength ([long]$file.Length) -ExpectedHash $copyItem.Hash `
            -CompletedBytes $completedBytes -TotalBytes ([long]$SourceInventory.TotalBytes) `
            -FolderName $FolderName -Language $Language -MessagesPath $MessagesPath -ProgressReporter $ProgressReporter
        $copiedFiles++
        $copiedBytes += [long]$file.Length
        $completedBytes += [long]$file.Length
    }
    if ($null -ne $ProgressReporter)
    {
        & $ProgressReporter -Activity $activity -Completed
    }

    [pscustomobject]@{
        CopiedFiles    = $copiedFiles
        IdenticalFiles = $identicalFiles
        CopiedBytes    = $copiedBytes
    }
}
