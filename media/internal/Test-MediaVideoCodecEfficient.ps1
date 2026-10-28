<#
.SYNOPSIS
    Classifies codecs that should not be re-encoded by the media optimizer.

.DESCRIPTION
    Defines Test-MediaVideoCodecEfficient, which identifies codecs already
    considered efficient for this optimizer.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Tests whether a video codec should be skipped.

.DESCRIPTION
    Returns true for H.264 at or below 1.9 Mb/s, or for HEVC, AV1, and VP9 at
    any bitrate. H.264 with unknown bitrate is skipped conservatively.

.PARAMETER Codec
    FFprobe codec name.

.PARAMETER VideoBitrate
    Video stream bitrate in bits per second. Zero means unknown.

.PARAMETER HasOriginalBackup
    Indicates that an _orig backup with the source extension already exists.

.OUTPUTS
    System.Boolean.
#>
function Test-MediaVideoCodecEfficient
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Codec,
        [long] $VideoBitrate = 0,
        [bool] $HasOriginalBackup = $false
    )

    $normalizedCodec = $Codec.Trim().ToLowerInvariant()
    if ($normalizedCodec -eq 'h264')
    {
        return $HasOriginalBackup -or $VideoBitrate -le 1900000
    }
    return $normalizedCodec -in @('hevc', 'av1', 'vp9')
}
