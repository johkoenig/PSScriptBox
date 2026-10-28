<#
.SYNOPSIS
    Reads the first video stream's codec and bitrate with FFprobe.

.DESCRIPTION
    Defines Get-MediaVideoInfo, which returns FFprobe's canonical codec name
    and bitrate for the first video stream.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7 and FFprobe.
    Uses Invoke-MediaTool and Get-LocalizedText.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Gets a media file's first video codec and bitrate.

.DESCRIPTION
    Selects the first video stream and requires FFprobe to return exactly one
    stream with a codec name. If the stream bitrate is unavailable, the format
    bitrate is used as a fallback; the bitrate is null if neither is available.

.PARAMETER Path
    Path to the media file.

.PARAMETER FFprobePath
    Path to the FFprobe executable.

.PARAMETER UiLanguage
    Language of error messages: 'de' selects German, anything else English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.OUTPUTS
    PSCustomObject with Codec (string) and Bitrate (nullable Int64, bits/second).
#>
function Get-MediaVideoInfo
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $FFprobePath,
        [string] $UiLanguage = 'en',
        [string]$MessagesPath = ''
    )
    $result = Invoke-MediaTool -ExecutablePath $FFprobePath -Arguments @(
        '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'stream=codec_name,bit_rate:format=bit_rate', '-of', 'json', $Path
    ) -UiLanguage $UiLanguage -MessagesPath $MessagesPath
    if ($result.ExitCode -ne 0)
    {
        $details = if ( [string]::IsNullOrWhiteSpace($result.StdErr))
        {
            $result.StdOut.Trim()
        }
        else
        {
            $result.StdErr.Trim()
        }
        throw (Get-LocalizedText -Text 'FFprobe failed for {0} (exit code {1}): {2}' -Arguments @($Path, $result.ExitCode, $details) -Language $UiLanguage -MessagesPath $MessagesPath)
    }

    try
    {
        $probeData = ConvertFrom-Json -InputObject $result.StdOut -ErrorAction Stop
    }
    catch
    {
        throw (Get-LocalizedText -Text 'FFprobe returned invalid video information for {0}: {1}' -Arguments @($Path, $_.Exception.Message) -Language $UiLanguage -MessagesPath $MessagesPath)
    }

    $streams = @($probeData.streams)
    if ($streams.Count -ne 1 -or
            -not $streams[0].PSObject.Properties['codec_name'] -or
            [string]::IsNullOrWhiteSpace([string]$streams[0].codec_name))
    {
        throw (Get-LocalizedText -Text 'FFprobe did not return exactly one video stream for {0}.' -Arguments @($Path) -Language $UiLanguage -MessagesPath $MessagesPath)
    }

    $bitrate = [long]0
    $streamBitrate = $streams[0].PSObject.Properties['bit_rate']
    if ($streamBitrate -and [long]::TryParse([string]$streamBitrate.Value, [ref]$bitrate) -and $bitrate -gt 0)
    {
        $videoBitrate = $bitrate
    }
    else
    {
        $formatBitrate = $null
        if ($probeData.format)
        {
            $formatBitrate = $probeData.format.PSObject.Properties['bit_rate']
        }
        $bitrate = [long]0
        if ($formatBitrate -and [long]::TryParse([string]$formatBitrate.Value, [ref]$bitrate) -and $bitrate -gt 0)
        {
            $videoBitrate = $bitrate
        }
        else
        {
            $videoBitrate = $null
        }
    }

    [pscustomobject]@{
        Codec = $streams[0].codec_name.Trim().ToLowerInvariant()
        Bitrate = $videoBitrate
    }
}
