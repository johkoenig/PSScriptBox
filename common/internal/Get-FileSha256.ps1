<#
.SYNOPSIS
    Provides the SHA-256 file hash helper shared by all tool folders.

.DESCRIPTION
    Defines Get-FileSha256. Has no dependencies on other helpers.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

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
