<#
.SYNOPSIS
    Determines whether and how to optimize a JPEG photo.

.DESCRIPTION
    Checks for the PSScriptBox processing marker first. Unmarked photos are
    measured with FFprobe and evaluated against density-first thresholds.

.PARAMETER Photo
    JPEG file to evaluate.

.PARAMETER FFprobePath
    Path to the FFprobe executable.

.PARAMETER ExifToolPath
    Path to the ExifTool executable.

.PARAMETER ExifToolConfigPath
    Path to the configuration defining the PSScriptBox XMP namespace.

.PARAMETER OptimizationMarkerValue
    Marker written to successfully optimized JPEG photos.

.PARAMETER SizeThresholdBytes
    File size above which a photo is eligible for proportional resizing.

.PARAMETER DensityThresholdMegabytesPerMegapixel
    Density above which a photo is eligible for recompression without resizing.

.PARAMETER UiLanguage
    Language of messages: 'de' selects the German catalog, anything else English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.EXAMPLE
    $plan = Get-MediaPhotoOptimizationPlan -Photo (Get-Item -LiteralPath 'C:\Photos\image.jpg') `
        -FFprobePath 'C:\Tools\ffprobe.exe' -ExifToolPath 'C:\Tools\exiftool.exe' `
        -ExifToolConfigPath '.\media\internal\exiftool.config'
    $plan.OptimizationMode

.NOTES
    Dependencies: FFprobe and ExifTool. Uses Invoke-MediaTool and Get-LocalizedText.

.OUTPUTS
    PSCustomObject with dimensions, density, eligibility, and optimization mode.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Copilot

<#
.SYNOPSIS
    Determines whether and how to optimize a JPEG photo.

.DESCRIPTION
    Checks for a PSScriptBox processing marker, then reads the photo dimensions
    with FFprobe and evaluates density before file size.

.PARAMETER Photo
    JPEG file to evaluate.

.PARAMETER FFprobePath
    Path to the FFprobe executable.

.PARAMETER ExifToolPath
    Path to the ExifTool executable.

.PARAMETER ExifToolConfigPath
    Path to the configuration defining the PSScriptBox XMP namespace.

.PARAMETER OptimizationMarkerValue
    Marker written to successfully optimized JPEG photos.

.PARAMETER SizeThresholdBytes
    File size above which a photo can be resized when its density is within
    the density threshold.

.PARAMETER DensityThresholdMegabytesPerMegapixel
    Density above which a photo is eligible for recompression without resizing.

.PARAMETER UiLanguage
    Language of messages: 'de' selects the German catalog, anything else English.

.PARAMETER MessagesPath
    Path to the German message catalog.

.EXAMPLE
    $plan = Get-MediaPhotoOptimizationPlan -Photo (Get-Item -LiteralPath 'C:\Photos\image.jpg') `
        -FFprobePath 'C:\Tools\ffprobe.exe' -ExifToolPath 'C:\Tools\exiftool.exe' `
        -ExifToolConfigPath '.\media\internal\exiftool.config'
    $plan.OptimizationMode

.NOTES
    Dependencies: FFprobe and ExifTool. Uses Invoke-MediaTool and Get-LocalizedText.

.OUTPUTS
    PSCustomObject with dimensions, density, eligibility, and optimization mode.
#>
function Get-MediaPhotoOptimizationPlan
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Photo,
        [Parameter(Mandatory)][string] $FFprobePath,
        [Parameter(Mandatory)][string] $ExifToolPath,
        [Parameter(Mandatory)][string] $ExifToolConfigPath,
        [string] $OptimizationMarkerValue = 'Optimize-MediaSize/photo-v1',
        [ValidateRange(1, [long]::MaxValue)][long] $SizeThresholdBytes = 6MB,
        [ValidateRange(0.0, [double]::MaxValue)][double] $DensityThresholdMegabytesPerMegapixel = 0.25,
        [string] $UiLanguage = 'en',
        [string] $MessagesPath = ''
    )

    $markerTag = '-XMP-psscriptbox:OptimizationProfile'
    $markerResult = Invoke-MediaTool -ExecutablePath $ExifToolPath -Arguments @(
        '-config', $ExifToolConfigPath, '-s3', $markerTag, $Photo.FullName
    ) -UiLanguage $UiLanguage -MessagesPath $MessagesPath
    if ($markerResult.ExitCode -ne 0)
    {
        $details = if ( [string]::IsNullOrWhiteSpace($markerResult.StdErr))
        {
            $markerResult.StdOut.Trim()
        }
        else
        {
            $markerResult.StdErr.Trim()
        }
        throw (Get-LocalizedText -Text 'ExifTool failed to check the optimization marker for {0} (exit code {1}): {2}' -Arguments @(
            $Photo.FullName, $markerResult.ExitCode, $details
        ) -Language $UiLanguage -MessagesPath $MessagesPath)
    }

    $existingMarker = $markerResult.StdOut.Trim()
    if ( $existingMarker.StartsWith('Optimize-MediaSize/photo-', [System.StringComparison]::OrdinalIgnoreCase))
    {
        return [pscustomobject]@{
            Width = [long]0
            Height = [long]0
            Megapixels = [double]0
            MegabytesPerMegapixel = [double]0
            OptimizationMode = $null
            ShouldOptimize = $false
            ProcessedByScript = $true
            SkipReason = Get-LocalizedText -Text 'JPEG was already optimized by this script (profile {0}); skipping.' -Arguments @(
                $existingMarker
            ) -Language $UiLanguage -MessagesPath $MessagesPath
        }
    }

    $dimensionResult = Invoke-MediaTool -ExecutablePath $FFprobePath -Arguments @(
        '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height',
        '-of', 'json', $Photo.FullName
    ) -UiLanguage $UiLanguage -MessagesPath $MessagesPath
    if ($dimensionResult.ExitCode -ne 0)
    {
        $details = if ( [string]::IsNullOrWhiteSpace($dimensionResult.StdErr))
        {
            $dimensionResult.StdOut.Trim()
        }
        else
        {
            $dimensionResult.StdErr.Trim()
        }
        throw (Get-LocalizedText -Text 'FFprobe failed to read JPEG dimensions for {0} (exit code {1}): {2}' -Arguments @(
            $Photo.FullName, $dimensionResult.ExitCode, $details
        ) -Language $UiLanguage -MessagesPath $MessagesPath)
    }

    try
    {
        $dimensionData = ConvertFrom-Json -InputObject $dimensionResult.StdOut -ErrorAction Stop
        $dimensionStreams = @($dimensionData.streams)
        if ($dimensionStreams.Count -ne 1 -or
                -not $dimensionStreams[0].PSObject.Properties['width'] -or
                -not $dimensionStreams[0].PSObject.Properties['height'])
        {
            throw 'FFprobe did not return one image stream with width and height.'
        }
        $sourceWidth = [long]$dimensionStreams[0].width
        $sourceHeight = [long]$dimensionStreams[0].height
        if ($sourceWidth -le 0 -or $sourceHeight -le 0)
        {
            throw 'FFprobe returned non-positive image dimensions.'
        }
    }
    catch
    {
        throw (Get-LocalizedText -Text 'FFprobe returned invalid JPEG dimensions for {0}: {1}' -Arguments @(
            $Photo.FullName, $_.Exception.Message
        ) -Language $UiLanguage -MessagesPath $MessagesPath)
    }

    $megapixels = ($sourceWidth * [double]$sourceHeight) / 1000000
    $megabytesPerMegapixel = ($Photo.Length / 1MB) / $megapixels
    $optimizationMode = if ($megabytesPerMegapixel -gt $DensityThresholdMegabytesPerMegapixel)
    {
        'Density'
    }
    elseif ($Photo.Length -gt $SizeThresholdBytes)
    {
        'Size'
    }
    else
    {
        $null
    }
    $skipReason = if ($null -eq $optimizationMode)
    {
        Get-LocalizedText -Text 'JPEG size {0:N1} MB and density {1:N3} MB/MP are at or below their optimization thresholds.' -Arguments @(
            ($Photo.Length / 1MB), $megabytesPerMegapixel
        ) -Language $UiLanguage -MessagesPath $MessagesPath
    }
    else
    {
        $null
    }

    [pscustomobject]@{
        Width = $sourceWidth
        Height = $sourceHeight
        Megapixels = $megapixels
        MegabytesPerMegapixel = $megabytesPerMegapixel
        OptimizationMode = $optimizationMode
        ShouldOptimize = ($null -ne $optimizationMode)
        ProcessedByScript = $false
        SkipReason = $skipReason
    }
}
