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
    files are copied with Robocopy's restartable mode and shown progress.
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
    Special user folder names requested for copying.

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
    Inventories files and directories beneath a folder.

.DESCRIPTION
    Erstellt relative Dateilisten und schließt konfigurierte Systemartefakte
    sowie Links aus. Virtuelle Nextcloud-Dateien und -Ordner sind Reparse
    Points ohne LinkType und werden deshalb für den Inhaltsvergleich
    berücksichtigt. Fehler bei der Auflistung werden gemeldet und nicht als
    erfolgreiche Teilliste behandelt.

.PARAMETER Path
    Vorhandener Ordner, der aufgelistet wird.

.OUTPUTS
    PSCustomObject mit den Eigenschaften Files, Directories, ReparsePoints
    und TotalBytes.
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
            if ($script:ExcludedNames -contains $item.Name) {
                continue
            }
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
        Files       = @($files.ToArray())
        Directories = @($directories.ToArray())
        ReparsePoints = @($reparsePoints.ToArray())
        TotalBytes  = $totalBytes
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
    Checks whether a file can be opened for reading.

.DESCRIPTION
    Opens an existing file for read access without reading or changing its
    contents.

.PARAMETER Path
    Existing file to check.

.OUTPUTS
    PSCustomObject with Path and Reason when read access is denied.
#>
function Test-FileReadAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Path
    )

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    }
    catch [System.UnauthorizedAccessException] {
        [pscustomobject]@{ Path = $Path; Reason = (Get-LocalizedText 'No read permission on file') }
    }
    catch [System.IO.IOException] {
        [pscustomobject]@{
            Path = $Path
            Reason = (Get-LocalizedText -Text 'File cannot be read: {0}' -Arguments @($_.Exception.Message))
        }
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

<#
.SYNOPSIS
    Runs Robocopy for one file while reporting live progress.

.DESCRIPTION
    Uses restartable mode, bounded retries, data/attribute/time copying, and
    asynchronous stream reading to keep Robocopy output from blocking.

.PARAMETER SourceDirectory
    Directory containing the source file.

.PARAMETER DestinationDirectory
    Existing or newly created destination directory.

.PARAMETER FileName
    Name of the file to copy.

.PARAMETER RelativePath
    File path relative to the selected user folder, used in progress and errors.

.PARAMETER FileLength
    Expected source file length.

.PARAMETER CompletedBytes
    Bytes already skipped or copied within the selected folder.

.PARAMETER TotalBytes
    Total source bytes in the selected folder.

.PARAMETER FolderName
    Display name of the selected user folder.
#>
function Invoke-RobocopyFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $SourceDirectory,
        [Parameter(Mandatory)][string] $DestinationDirectory,
        [Parameter(Mandatory)][string] $FileName,
        [Parameter(Mandatory)][string] $RelativePath,
        [Parameter(Mandatory)][long] $FileLength,
        [Parameter(Mandatory)][long] $CompletedBytes,
        [Parameter(Mandatory)][long] $TotalBytes,
        [Parameter(Mandatory)][string] $FolderName
    )

    $robocopy = Get-Command -Name 'robocopy.exe' -CommandType Application -ErrorAction Stop
    [System.IO.Directory]::CreateDirectory($DestinationDirectory) | Out-Null

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $robocopy.Source
    $startInfo.Arguments = '"{0}" "{1}" "{2}" /Z /R:2 /W:1 /COPY:DAT /DCOPY:DAT /XJ /IS /IT' -f @(
        $SourceDirectory, $DestinationDirectory, $FileName
    )
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $outputLines = [System.Collections.Generic.List[string]]::new()
    $errorLines = [System.Collections.Generic.List[string]]::new()
    $activity = Get-LocalizedText -Text 'Copying folder {0}' -Arguments @($FolderName)
    $status = Get-LocalizedText -Text 'Copying file: {0}' -Arguments @($RelativePath)

    try {
        if (-not $process.Start()) {
            throw (Get-LocalizedText -Text 'Could not start Robocopy for {0}.' -Arguments @($RelativePath))
        }
        $standardOutputTask = $process.StandardOutput.ReadLineAsync()
        $standardErrorTask = $process.StandardError.ReadLineAsync()
        $standardOutputEnded = $false
        $standardErrorEnded = $false

        while (-not $process.HasExited -or -not $standardOutputEnded -or -not $standardErrorEnded) {
            $receivedLine = $false
            if (-not $standardOutputEnded -and $standardOutputTask.IsCompleted) {
                $line = $standardOutputTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $standardOutputEnded = $true
                }
                else {
                    if ($outputLines.Count -ge 12) { $outputLines.RemoveAt(0) }
                    $outputLines.Add($line)
                    if ($line -match '^\s*(\d+(?:[\.,]\d+)?)%\s*$') {
                        $filePercent = [double]::Parse(
                            $matches[1].Replace(',', '.'),
                            [System.Globalization.CultureInfo]::InvariantCulture
                        )
                        if ($TotalBytes -gt 0) {
                            $overallPercent = (($CompletedBytes + ($FileLength * $filePercent / 100)) / $TotalBytes) * 100
                        }
                        else {
                            $overallPercent = $filePercent
                        }
                        Write-Progress -Activity $activity -Status $status `
                            -PercentComplete ([Math]::Min(100, [Math]::Max(0, [int]$overallPercent)))
                    }
                    $standardOutputTask = $process.StandardOutput.ReadLineAsync()
                }
                $receivedLine = $true
            }

            if (-not $standardErrorEnded -and $standardErrorTask.IsCompleted) {
                $line = $standardErrorTask.GetAwaiter().GetResult()
                if ($null -eq $line) {
                    $standardErrorEnded = $true
                }
                else {
                    if ($errorLines.Count -ge 12) { $errorLines.RemoveAt(0) }
                    $errorLines.Add($line)
                    $standardErrorTask = $process.StandardError.ReadLineAsync()
                }
                $receivedLine = $true
            }

            if (-not $receivedLine) { Start-Sleep -Milliseconds 50 }
        }
        $process.WaitForExit()

        if ($process.ExitCode -ge 8) {
            $details = @($errorLines.ToArray()) + @($outputLines.ToArray())
            $details = (($details | Select-Object -Last 8) -join ' ').Trim()
            if ([string]::IsNullOrWhiteSpace($details)) {
                $details = Get-LocalizedText 'No diagnostic output was returned.'
            }
            throw (Get-LocalizedText -Text 'Robocopy failed for {0} (exit code {1}): {2}' -Arguments @(
                $RelativePath, $process.ExitCode, $details
            ))
        }
    }
    finally {
        $process.Dispose()
    }

    $destinationFilePath = Join-Path $DestinationDirectory $FileName
    if (-not (Test-Path -LiteralPath $destinationFilePath -PathType Leaf)) {
        throw (Get-LocalizedText -Text 'Robocopy did not create the destination file: {0}' -Arguments @($RelativePath))
    }
}

<#
.SYNOPSIS
    Copies non-identical files and verifies destination content.

.DESCRIPTION
    Skips a source file when any file in the destination has the same SHA-256
    hash. Transfers other files with Robocopy and verifies copied content.

.PARAMETER Source
    Source folder.

.PARAMETER Destination
    Existing destination folder.

.PARAMETER SourceInventory
    Inventory captured before copying.

.PARAMETER DestinationInventory
    Inventory captured before copying.

.OUTPUTS
    PSCustomObject with copied and identical file counts and copied bytes.
#>
function Copy-ChangedFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Destination,
        [Parameter(Mandatory)][psobject] $SourceInventory,
        [Parameter(Mandatory)][psobject] $DestinationInventory,
        [Parameter(Mandatory)][string] $FolderName
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
    $activity = Get-LocalizedText -Text 'Copying folder {0}' -Arguments @($FolderName)
    for ($i = 0; $i -lt $SourceInventory.Files.Count; $i++) {
        $file = $SourceInventory.Files[$i]
        if ($SourceInventory.Files.Count -gt 0) {
            $checkPercent = [int](100 * $i / $SourceInventory.Files.Count)
            Write-Progress -Activity $activity `
                -Status (Get-LocalizedText 'Checking files for identical content') `
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
                throw (Get-LocalizedText -Text 'Source file changed while checking for identical content: {0}' -Arguments @($file.RelativePath))
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
        Invoke-RobocopyFile -SourceDirectory $sourceFileDirectory `
            -DestinationDirectory $destinationFileDirectory -FileName $sourceFileName `
            -RelativePath $file.RelativePath -FileLength ([long]$file.Length) `
            -CompletedBytes $completedBytes -TotalBytes ([long]$SourceInventory.TotalBytes) `
            -FolderName $FolderName
        $sourceHashAfterCopy = Get-FileSha256 -Path $sourceFilePath
        $destinationHash = Get-FileSha256 -Path $destinationFilePath
        if ($sourceHashAfterCopy -ne $copyItem.Hash -or $destinationHash -ne $copyItem.Hash) {
            throw (Get-LocalizedText -Text 'File content does not match at destination: {0}' -Arguments @($file.RelativePath))
        }
        $copiedFiles++
        $copiedBytes += [long]$file.Length
        $completedBytes += [long]$file.Length
    }
    Write-Progress -Activity $activity -Completed

    [pscustomobject]@{
        CopiedFiles    = $copiedFiles
        IdenticalFiles = $identicalFiles
        CopiedBytes    = $copiedBytes
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

    $userFolders = @(Get-UserFolders -Names @($Folders | Select-Object -Unique))
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
            foreach ($problem in @(Test-FileReadAccess -Path $filePath)) {
                $accessProblems.Add($problem)
            }
        }
        foreach ($file in $migration.DestinationInventory.Files) {
            $filePath = Join-Path $migration.DestinationPath $file.RelativePath
            foreach ($problem in @(Test-FileReadAccess -Path $filePath)) {
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
                -FolderName $folder.Name
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
