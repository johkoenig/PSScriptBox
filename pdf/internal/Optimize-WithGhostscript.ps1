<#
.SYNOPSIS
    Provides the Ghostscript optimization helper for the OCR script.

.DESCRIPTION
    Defines Optimize-WithGhostscript, which runs the optional Ghostscript
    downsampling stage on a processed PDF.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7. Uses ConvertTo-QuotedArgument.
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

.OUTPUTS
    System.Boolean. $true if the file was successfully reduced in size.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $GhostscriptPath,
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][int] $Dpi
    )

    $tempPath = Join-Path $Pdf.DirectoryName ('.{0}.gs.pdf.part' -f [guid]::NewGuid().ToString('N'))
    try {
        # Explicit downsampling parameters guarantee the target resolution for
        # color, grayscale, and monochrome images, embedded as JPEG.
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
            '-dJPEGQ=75',
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
            if (-not $process.Start()) { return $false }
            # Read streams asynchronously to prevent pipe deadlocks.
            $process.StandardOutput.ReadToEndAsync() | Out-Null
            $process.StandardError.ReadToEndAsync() | Out-Null
            $process.WaitForExit()
            if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $tempPath)) { return $false }
        }
        finally { $process.Dispose() }
        $originalSize = $Pdf.Length
        $optimizedSize = (Get-Item -LiteralPath $tempPath).Length
        if ($optimizedSize -ge $originalSize) { return $false }
        Remove-Item -LiteralPath $Pdf.FullName -Force
        Move-Item -LiteralPath $tempPath -Destination $Pdf.FullName -Force
        return $true
    }
    catch { return $false }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}
