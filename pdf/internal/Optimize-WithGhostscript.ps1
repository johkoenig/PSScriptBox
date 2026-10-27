<#
.SYNOPSIS
    Provides the Ghostscript image optimization helper.

.DESCRIPTION
    Defines Optimize-WithGhostscript, which downsamples PDF images and keeps the
    Ghostscript output only when it is smaller than the input.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Uses ConvertTo-QuotedArgument from common\internal.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

function Optimize-WithGhostscript {
<#
.SYNOPSIS
    Optimizes a PDF file with Ghostscript.

.DESCRIPTION
    Downsamples images at the specified resolution and JPEG quality. Replaces
    the input file only if the result is smaller. The temporary output is
    removed in all cases.

.PARAMETER GhostscriptPath
    Path to the Ghostscript executable.

.PARAMETER Pdf
    PDF file to optimize.

.PARAMETER Dpi
    Target resolution for downsampling.

.PARAMETER Quality
    JPEG quality for downsampled images.

.OUTPUTS
    System.Boolean. $true if the file was reduced, $false if the output was not
    smaller. Process and output failures are thrown to the caller.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $GhostscriptPath,
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][int] $Dpi,
        [Parameter(Mandatory)][int] $Quality
    )

    $tempPath = Join-Path $Pdf.DirectoryName ('.{0}.gs.pdf.part' -f [guid]::NewGuid().ToString('N'))
    try {
        # Explicit downsampling parameters set the target resolution for all
        # image types; color and grayscale images use JPEG encoding.
        # -dCompatibilityLevel=1.5 sets the output PDF version to 1.5.
        $gsArgList = @(
            '-dBATCH', '-dNOPAUSE', '-dQUIET',
            '-sDEVICE=pdfwrite',
            '-dDownsampleColorImages=true',
            '-dDownsampleGrayImages=true',
            '-dDownsampleMonoImages=true',
            "-dColorImageResolution=$Dpi",
            "-dGrayImageResolution=$Dpi",
            "-dMonoImageResolution=$Dpi",
            '-dColorImageFilter=/DCTEncode',
            '-dGrayImageFilter=/DCTEncode',
            '-dAutoFilterColorImages=false',
            '-dAutoFilterGrayImages=false',
            '-dColorConversionStrategy=/sRGB',
            '-dColorConversionStrategyForImages=/sRGB',
            "-dJPEGQ=$Quality",
            '-dCompatibilityLevel=1.5',
            ('-sOutputFile={0}' -f $tempPath),
            $Pdf.FullName
        )
        $argsString = ($gsArgList | ForEach-Object { ConvertTo-QuotedArgument -Value $_ }) -join ' '
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $GhostscriptPath
        $startInfo.Arguments = $argsString
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        try {
            if (-not $process.Start())
            {
                throw 'Ghostscript could not be started.'
            }
            # Read streams asynchronously to prevent pipe deadlocks.
            $standardOutput = $process.StandardOutput.ReadToEndAsync()
            $standardError = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            $outputText = $standardOutput.GetAwaiter().GetResult()
            $errorText = $standardError.GetAwaiter().GetResult()
            if ($process.ExitCode -ne 0)
            {
                $details = if ($errorText)
                {
                    $errorText
                }
                else
                {
                    $outputText
                }
                throw "Ghostscript exited with code $( $process.ExitCode ): $details"
            }
            if (-not (Test-Path -LiteralPath $tempPath))
            {
                throw 'Ghostscript did not produce an output file.'
            }
        }
        finally { $process.Dispose() }
        $originalSize = $Pdf.Length
        $optimizedSize = (Get-Item -LiteralPath $tempPath).Length
        if ($optimizedSize -ge $originalSize) { return $false }
        Remove-Item -LiteralPath $Pdf.FullName -Force
        Move-Item -LiteralPath $tempPath -Destination $Pdf.FullName -Force
        return $true
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}
