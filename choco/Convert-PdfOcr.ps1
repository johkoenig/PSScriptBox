<#
.SYNOPSIS
    Optimiert PDFs, korrigiert Scan-Seiten und ergänzt eine OCR-Textebene.
.DESCRIPTION
    Verarbeitet eine PDF-Datei oder PDFs in einem Ordner. Standardmäßig wird die
    Eingabedatei nach erfolgreicher OCR durch das Ergebnis ersetzt. Mit -KeepOriginal
    wird das Original stattdessen als <Name>_raw.pdf gesichert.
#>
[CmdletBinding()]
param(
    [string] $Language,
    [string] $InputPath,
    [ValidateRange(1,100)][int] $JpegQuality = 75,
    [ValidateRange(0,1200)][int] $GhostscriptDpi = 0,
    [switch] $Deskew,
    [switch] $RotatePages,
    [switch] $NoGhostscript,
    [switch] $KeepOriginal
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:DefaultLanguage = 'deu+eng+fra+ita+spa'
$script:RequiredLanguages = @('deu','eng')
$script:TessdataUrl = 'https://github.com/tesseract-ocr/tessdata_best'

function Quote-Argument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Value)
    $escaped = [regex]::Replace($Value, '(\\)(?=")', '$1$1')
    if ($escaped.EndsWith('\')) { $escaped += '\' }
    $escaped = $escaped -replace '"', '\"'
    return '"' + $escaped + '"'
}
function Get-ExecutablePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)
    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) { return $null }
    return $command.Source
}
function Test-PythonModule {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $PythonPath,[Parameter(Mandatory)][string] $ModuleName)
    $p = [System.Diagnostics.ProcessStartInfo]::new()
    $p.FileName = $PythonPath
    $p.Arguments = "-c `"import $ModuleName`""
    $p.UseShellExecute = $false; $p.CreateNoWindow = $true
    $p.RedirectStandardOutput = $true; $p.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::new(); $proc.StartInfo = $p
    try {
        if (-not $proc.Start()) { return $false }
        $out = $proc.StandardOutput.ReadToEndAsync(); $err = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit(); $out.GetAwaiter().GetResult() | Out-Null; $err.GetAwaiter().GetResult() | Out-Null
        return ($proc.ExitCode -eq 0)
    } catch { return $false } finally { $proc.Dispose() }
}
function Get-TesseractLanguages {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $TesseractPath)
    $p = [System.Diagnostics.ProcessStartInfo]::new()
    $p.FileName = $TesseractPath; $p.Arguments = '--list-langs'
    $p.UseShellExecute = $false; $p.CreateNoWindow = $true
    $p.RedirectStandardOutput = $true; $p.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::new(); $proc.StartInfo = $p
    try {
        if (-not $proc.Start()) { throw 'Tesseract konnte nicht gestartet werden.' }
        $outTask = $proc.StandardOutput.ReadToEndAsync(); $errTask = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit(); $out = $outTask.GetAwaiter().GetResult(); $err = $errTask.GetAwaiter().GetResult()
        if ($proc.ExitCode -ne 0) { throw "Tesseract --list-langs fehlgeschlagen: $err" }
    } finally { $proc.Dispose() }
    $data = $null
    if ($out -match 'List of available languages in "([^"]+)"') { $data = $Matches[1] }
    if (-not $data) { $data = Join-Path (Split-Path -Parent $TesseractPath) 'tessdata' }
    $langs = @($out -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^List of available languages' })
    [pscustomobject]@{ Languages=$langs; TessdataPath=$data }
}
function Get-PdfInputFile {
    [CmdletBinding()]
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Read-Host 'Pfad zu einer PDF-Datei oder einem Ordner mit PDFs' }
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Es wurde kein Pfad eingegeben.' }
    $Path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (-not (Test-Path -LiteralPath $Path)) { throw "Pfad nicht gefunden: $Path" }
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) { return @(Get-ChildItem -LiteralPath $item.FullName -File -Filter '*.pdf') }
    if ($item.Extension -ine '.pdf') { throw 'Die ausgewählte Datei hat keine .pdf-Endung.' }
    return @($item)
}
function Get-FileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $stream=[System.IO.File]::OpenRead($Path); try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') } finally { $stream.Dispose() } }
    finally { $sha.Dispose() }
}
function Optimize-WithGhostscript {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $GhostscriptPath,[Parameter(Mandatory)][System.IO.FileInfo] $Pdf,[Parameter(Mandatory)][int] $Dpi)
    $tmp = Join-Path $Pdf.DirectoryName ('.{0}.{1}.gs.tmp.pdf' -f $Pdf.BaseName,[guid]::NewGuid().ToString('N'))
    try {
        $list = @('-dBATCH','-dNOPAUSE','-dQUIET','-sDEVICE=pdfwrite','-dDownsampleColorImages=true','-dDownsampleGrayImages=true','-dDownsampleMonoImages=true',"-dColorImageResolution=$Dpi","-dGrayImageResolution=$Dpi","-dMonoImageResolution=$Dpi",'-dColorImageFilter=/DCTEncode','-dGrayImageFilter=/DCTEncode','-dAutoFilterColorImages=false','-dAutoFilterGrayImages=false','-dColorConversionStrategy=/sRGB','-dColorConversionStrategyForImages=/sRGB','-dJPEGQ=75','-dCompatibilityLevel=1.5',("-sOutputFile={0}" -f $tmp),$Pdf.FullName)
        $si=[System.Diagnostics.ProcessStartInfo]::new(); $si.FileName=$GhostscriptPath
        $si.Arguments=($list | ForEach-Object { Quote-Argument $_ }) -join ' '
        $si.UseShellExecute=$false; $si.CreateNoWindow=$true; $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true
        $proc=[System.Diagnostics.Process]::new(); $proc.StartInfo=$si
        try { if (-not $proc.Start()) { return $false }; $o=$proc.StandardOutput.ReadToEndAsync(); $e=$proc.StandardError.ReadToEndAsync(); $proc.WaitForExit(); $o.GetAwaiter().GetResult()|Out-Null; $e.GetAwaiter().GetResult()|Out-Null; if ($proc.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $tmp)) { return $false } } finally { $proc.Dispose() }
        if ((Get-Item -LiteralPath $tmp).Length -ge $Pdf.Length) { return $false }
        Move-Item -LiteralPath $tmp -Destination $Pdf.FullName -Force
        return $true
    } catch { return $false } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
}
function Invoke-PdfProcessing {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.IO.FileInfo] $Pdf,[Parameter(Mandatory)][string] $PythonPath,[Parameter(Mandatory)][string] $Language,[Parameter(Mandatory)][int] $Quality,[Parameter(Mandatory)][int] $GhostscriptDpi,[Parameter(Mandatory)][bool] $Deskew,[Parameter(Mandatory)][bool] $RotatePages,[Parameter(Mandatory)][bool] $NoGhostscript,[Parameter(Mandatory)][bool] $KeepOriginal,[string] $GhostscriptPath)
    $temp = Join-Path $Pdf.DirectoryName ('.{0}.{1}.tmp.pdf' -f $Pdf.BaseName,[guid]::NewGuid().ToString('N'))
    $rawPath = Join-Path $Pdf.DirectoryName ($Pdf.BaseName + '_raw' + $Pdf.Extension)
    try {
        Write-Host "Bearbeite: $($Pdf.Name)"
        $args = @('--skip-text','--output-type','pdf','--optimize','1','--jpeg-quality',$Quality,'--language',$Language)
        if ($Deskew) { $args += '--deskew' }
        if ($RotatePages) { $args += @('--rotate-pages','--rotate-pages-threshold','2.0') }
        & $PythonPath -m ocrmypdf @args -- $Pdf.FullName $temp
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temp)) { throw "OCRmyPDF fehlgeschlagen (Exitcode $LASTEXITCODE)." }
        if (-not $NoGhostscript -and $GhostscriptDpi -gt 0 -and $GhostscriptPath) { Optimize-WithGhostscript -GhostscriptPath $GhostscriptPath -Pdf (Get-Item -LiteralPath $temp) -Dpi $GhostscriptDpi | Out-Null }
        $originalSize=(Get-Item -LiteralPath $Pdf.FullName).Length; $resultSize=(Get-Item -LiteralPath $temp).Length
        if ((Get-FileSha256 $Pdf.FullName) -eq (Get-FileSha256 $temp)) { Write-Host 'Ergebnis unverändert; wird verworfen.' -ForegroundColor Yellow; return [pscustomobject]@{Success=$false;OriginalBytes=$originalSize;ResultBytes=0} }
        if ($KeepOriginal) {
            if (Test-Path -LiteralPath $rawPath) { Remove-Item -LiteralPath $rawPath -Force }
            Move-Item -LiteralPath $Pdf.FullName -Destination $rawPath -Force
            try { Move-Item -LiteralPath $temp -Destination $Pdf.FullName -Force }
            catch { Move-Item -LiteralPath $rawPath -Destination $Pdf.FullName -Force; throw }
            Write-Host "Original gesichert: $rawPath"
        } else { Move-Item -LiteralPath $temp -Destination $Pdf.FullName -Force }
        Write-Host "Überschrieben: $($Pdf.FullName)"
        return [pscustomobject]@{Success=$true;OriginalBytes=[long]$originalSize;ResultBytes=[long]$resultSize}
    } catch { Write-Warning "Fehler bei '$($Pdf.Name)': $($_.Exception.Message)"; return [pscustomobject]@{Success=$false;OriginalBytes=[long]0;ResultBytes=[long]0} }
    finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } }
}

Write-Host ''
Write-Host '  +---------------------------------------------+' -ForegroundColor Cyan
Write-Host '  |  ____  ____  _____        ___   ____ ____   |' -ForegroundColor Cyan
Write-Host '  | |  _ \/ ___|| ____|      / _ \ / ___|  _ \  |' -ForegroundColor Cyan
Write-Host '  | | |_) \___ \|  _| _____| | | | |   | |_) | |' -ForegroundColor Cyan
Write-Host '  | |  __/ ___) | |__|_____| |_| | |___|  _ <  |' -ForegroundColor Cyan
Write-Host '  | |_|   |____/|_____|     \___/ \____|_| \_\ |' -ForegroundColor Cyan
Write-Host '  +---------------------------------------------+' -ForegroundColor Cyan
Write-Host '  PDF-OCR: OCR, Begradigung und optionale Komprimierung' -ForegroundColor Cyan

$pythonPath=Get-ExecutablePath 'py'; if (-not $pythonPath) { $pythonPath=Get-ExecutablePath 'python' }
$tesseractPath=Get-ExecutablePath 'tesseract'
$gsPath=Get-ExecutablePath 'gswin64c'; if (-not $gsPath) { $gsPath=Get-ExecutablePath 'gswin32c' }; if (-not $gsPath) { $gsPath=Get-ExecutablePath 'gs' }
$missing=@(); if (-not $pythonPath) {$missing+='Python (py.exe oder python.exe)'}; if (-not $tesseractPath) {$missing+='Tesseract'}
if ($pythonPath -and -not (Test-PythonModule $pythonPath 'ocrmypdf')) {$missing+='OCRmyPDF (Python-Modul)'}
if ($missing.Count) { Write-Host "Fehlende Abhängigkeiten: $($missing -join ', ')" -ForegroundColor Yellow; Write-Host 'Installation: choco install python tesseract ghostscript -y'; Write-Host 'py -m pip install --user ocrmypdf'; exit 1 }
if (-not $NoGhostscript -and -not $gsPath) { Write-Host 'Ghostscript fehlt; optionale Optimierung wird übersprungen.' -ForegroundColor DarkYellow }
try { $pdfFiles=@(Get-PdfInputFile $InputPath) } catch { Write-Error $_.Exception.Message; exit 1 }
if (-not $pdfFiles.Count) { Write-Host 'Keine PDFs gefunden.'; exit 0 }
try { $ti=Get-TesseractLanguages $tesseractPath } catch { Write-Error $_.Exception.Message; exit 1 }
$installed=@($ti.Languages); $selection=if ([string]::IsNullOrWhiteSpace($Language)) {$script:DefaultLanguage} else {$Language.Trim()}
$requested=@($selection -split '\+' | ForEach-Object {$_.Trim()} | Where-Object {$_})
$missingRequired=@($requested | Where-Object {$script:RequiredLanguages -contains $_ -and $installed -notcontains $_})
if ($missingRequired.Count) { Write-Host "Fehlende Pflicht-Sprachdaten: $($missingRequired -join ', ')"; Write-Host "Download: $script:TessdataUrl — tessdata-Ordner: $($ti.TessdataPath)"; exit 1 }
$dropped=@($requested | Where-Object {$installed -notcontains $_}); if ($dropped.Count) { Write-Host "Nicht installierte Sprachen entfernt: $($dropped -join ', ')" -ForegroundColor DarkYellow }
$selection=(@($requested | Where-Object {$installed -contains $_}) -join '+')
$results=@(); for ($i=0;$i -lt $pdfFiles.Count;$i++) { $pdf=$pdfFiles[$i]; Write-Host "--- Datei $($i+1)/$($pdfFiles.Count): $($pdf.Name) ---" -ForegroundColor Cyan; $r=Invoke-PdfProcessing -Pdf $pdf -PythonPath $pythonPath -Language $selection -Quality $JpegQuality -GhostscriptDpi $GhostscriptDpi -Deskew ([bool]$Deskew) -RotatePages ([bool]$RotatePages) -NoGhostscript ([bool]$NoGhostscript) -KeepOriginal ([bool]$KeepOriginal) -GhostscriptPath $gsPath; $results += $r }
$success=@($results | Where-Object {$_.Success}); $fail=@($results | Where-Object {-not $_.Success}); Write-Host "Zusammenfassung: Erfolgreich $($success.Count), fehlgeschlagen $($fail.Count)" -ForegroundColor Cyan
