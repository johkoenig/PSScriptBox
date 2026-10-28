<#
.SYNOPSIS
    Provides the folder inventory helper for the Nextcloud scripts.

.DESCRIPTION
    Defines Get-FolderInventory. Has no dependencies on other helpers.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Inventories files and directories beneath a folder.

.DESCRIPTION
    Produces a relative-path inventory while excluding configured system
    artifacts and links (symbolic links, junctions). Nextcloud virtual files
    and folders are reparse points without a link type; they are included, so
    their content can be hashed. Enumeration errors terminate the inventory.

.PARAMETER Path
    Existing folder to inventory.

.PARAMETER ExcludedNames
    Item names skipped at every level of the tree, such as system artifacts.

.OUTPUTS
    PSCustomObject with Files, Directories, ReparsePoints, and TotalBytes.
#>
function Get-FolderInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Path,
        [string[]] $ExcludedNames = @('$RECYCLE.BIN', 'desktop.ini', 'Thumbs.db', 'System Volume Information')
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
            if ($ExcludedNames -contains $item.Name) { continue }
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
