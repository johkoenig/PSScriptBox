<#
.SYNOPSIS
    Optimiert PDFs und ergänzt bei Bedarf eine OCR-Textebene.

.DESCRIPTION
    Verarbeitet eine einzelne PDF-Datei oder alle PDF-Dateien direkt in
    einem angegebenen Ordner (keine Unterordner). Erstellt vor der
    Verarbeitung eine Sicherung mit dem Suffix _orig. Das Original wird
    nur durch ein erfolgreich verarbeitetes, kleineres Ergebnis ersetzt.

    KOMPRESSION:
      OCRmyPDF liefert eine komprimierte PDF. Ist Ghostscript aktiv
      (-UseGhostscript), wird die Datei nachgelagert mit Ghostscript auf
      200 DPI (JPEG Qualität 75) neu gerendert; das Original bleibt nur
      bei tatsächlicher Verkleinerung erhalten.

    SPRACHEN:
      Standard ist deu+eng+fra+ita+spa. Eine abweichende Sprachfolge kann
      per Parameter oder interaktiv vorgegeben werden.

    ERGEBNISPRÜFUNG:
      Wird das Ergebnis nicht kleiner als das Original, bleibt die Datei
      unverändert (und es wird keine _orig-Sicherung angelegt). Nach der
      OCR/Optimierung wird ein SHA256-Vergleich gegen die Eingabedatei
      durchgeführt; identische Hashes werden nicht überschrieben.

.PARAMETER Language
    OCR-Sprachfolge (z. B. deu+eng). Standard: deu+eng+fra+ita+spa.

.PARAMETER InputPath
    Pfad zu einer PDF-Datei oder einem Ordner mit PDFs.
    Ohne Angabe wird interaktiv danach gefragt.

.PARAMETER JpegQuality
    JPEG-Qualität für OCRmyPDF-Optimierung (1-100). Standard: 75.

.PARAMETER ImageDpi
    Zielauflösung für eingebettete Bilder. Hinweis: OCRmyPDF ignoriert
    --image-dpi bei PDF-Eingaben. Ghostscript legt die endgültige
    Bildauflösung auf 200 DPI fest (JPEG Qualität 75); eine kleinere
    Auflösung ist nicht vorgesehen.

.PARAMETER Deskew
    Optionale automatische Begradigung.

.PARAMETER RotatePages
    Seitengenaue Rotation anhand Tesseract-Analyse.

.PARAMETER UseQpdf
    Strukturelle Optimierung mit qpdf als nachgelagerter Schritt.

.PARAMETER UseGhostscript
    Kompression mit Ghostscript (200 DPI, JPEG q75) als nachgelagerter
    Schritt.

.EXAMPLE
    .\pdf-toolbox.ps1

.EXAMPLE
    .\pdf-toolbox.ps1 -InputPath 'X:\Scans' -Language deu+eng -UseGhostscript

.NOTES
    Abhängigkeiten:
      - Python
      - OCRmyPDF (Python-Modul)
      - Tesseract

    Beispielinstallation aus einer PowerShell mit Administratorrechten:
      choco install python tesseract -y
      py -m pip install --user ocrmypdf

    Sprachdaten (traineddata) sind separat für Tesseract zu installieren.
    Siehe https://github.com/tesseract-ocr/tessdata . Die benötigten Dateien
    gehören in den tessdata-Ordner von Tesseract. Danach
    `tesseract --list-langs` ausführen und eine neue PowerShell-Sitzung
    öffnen.

    Kompatibilität: Windows PowerShell 5.1 - ProcessStartInfo.ArgumentList
    ist nicht verfügbar; stattdessen wird Arguments als String mit
    korrekter Windows-Quotierung übergeben. Pfade mit Leerzeichen und
    inneren Anführungszeichen werden über die Hilfsfunktion Quote-Argument
    verpackt.

    Ausgabe: OCRmyPDF schreibt Fortschrittsbalken und Statusmeldungen
    direkt auf die Konsole (Live-Ausgabe, wird nicht gefiltert).

    Ghostscript-Stufe: 200 DPI (nicht unter 200 DPI).
#>

[CmdletBinding()]
param(
    [string] $Language,

    [string] $InputPath,

    [ValidateRange(1, 100)]
    [int] $JpegQuality = 75,

    [ValidateRange(50, 1200)]
    [int] $ImageDpi = 300,

    [bool] $Deskew = $true,

    [bool] $RotatePages = $false,

    [bool] $UseQpdf = $false,

    [bool] $UseGhostscript = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Standard-Sprachfolge: Deutsch, Englisch, Französisch,
# Italienisch, Spanisch - in dieser Reihenfolge.
$script:DefaultLanguage = 'deu+eng+fra+ita+spa'
$script:RequiredLanguages = @('deu', 'eng')

# --- Hilfsfunktionen ------------------------------------------------------

# Setzt ein Argument in doppelte Anführungszeichen und escaped innere
# doppelte Anführungszeichen sowie abschließende Backslashes so, dass es
# über ProcessStartInfo.Arguments unter Windows PowerShell 5.1 korrekt
# übergeben wird.
function Quote-Argument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Value)

    # Jeden Backslash vor einem Anführungszeichen verdoppeln.
    $escaped = [regex]::Replace($Value, '(\\)(?=")', '$1$1')
    # Verbleibende abschließende Backslashes verdoppeln.
    if ($escaped.EndsWith('\')) { $escaped = $escaped + '\' }
    # Innere doppelte Anführungszeichen escapen.
    $escaped = $escaped -replace '"', '\"'
    return '"' + $escaped + '"'
}

function Get-ExecutablePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) { return $null }
    return $command.Source
}

function Test-PythonModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string] $ModuleName
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $PythonPath
    $startInfo.Arguments = '-c "import ' + $ModuleName + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { return $false }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdoutTask.GetAwaiter().GetResult() | Out-Null
        $stderrTask.GetAwaiter().GetResult() | Out-Null
        return ($process.ExitCode -eq 0)
    }
    catch { return $false }
    finally { $process.Dispose() }
}

function Get-MissingDependency {
    [CmdletBinding()]
    param()

    $missing = [System.Collections.Generic.List[string]]::new()
    $optionalMissing = [System.Collections.Generic.List[string]]::new()
    $pythonPath = Get-ExecutablePath -Name 'py'
    if (-not $pythonPath) { $pythonPath = Get-ExecutablePath -Name 'python' }
    if (-not $pythonPath) { $missing.Add('Python (py.exe oder python.exe)') }
    if (-not (Get-ExecutablePath -Name 'tesseract')) { $missing.Add('Tesseract') }

    $ghostscriptPath = Get-ExecutablePath -Name 'gswin64c'
    if (-not $ghostscriptPath) { $ghostscriptPath = Get-ExecutablePath -Name 'gswin32c' }
    if (-not $ghostscriptPath) { $ghostscriptPath = Get-ExecutablePath -Name 'gs' }
    if (-not $ghostscriptPath) { $missing.Add('Ghostscript') }

    $qpdfPath = Get-ExecutablePath -Name 'qpdf'

    if ($pythonPath -and -not (Test-PythonModule -PythonPath $pythonPath -ModuleName 'ocrmypdf')) {
        $missing.Add('OCRmyPDF (Python-Modul)')
    }

    [pscustomobject]@{
        PythonPath      = $pythonPath
        QpdfPath        = $qpdfPath
        GhostscriptPath = $ghostscriptPath
        Missing         = $missing
        OptionalMissing = $optionalMissing
    }
}

function Get-PdfInputFile {
    [CmdletBinding()]
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Read-Host 'Pfad zu einer PDF-Datei oder einem Ordner mit PDFs'
    }
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Es wurde kein Pfad eingegeben.' }
    $Path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (-not (Test-Path -LiteralPath $Path)) { throw "Pfad nicht gefunden: $Path" }
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) {
        return @(Get-ChildItem -LiteralPath $item.FullName -File -Filter '*.pdf')
    }
    if ($item.Extension -ine '.pdf') { throw 'Die ausgewählte Datei hat keine .pdf-Endung.' }
    return @($item)
}

function Get-FileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $hashBytes = $sha256.ComputeHash($stream)
            return ([BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
        }
        finally { $stream.Dispose() }
    }
    finally { $sha256.Dispose() }
}

# Optimiert eine PDF-Datei strukturell mit qpdf.
function Optimize-WithQpdf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $QpdfPath,
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf
    )

    $tempPath = Join-Path $Pdf.DirectoryName ('.{0}.{1}.qpdf.tmp.pdf' -f $Pdf.BaseName, [guid]::NewGuid().ToString('N'))
    try {
        $argList = @('--linearize', $Pdf.FullName, $tempPath)
        $argsString = ($argList | ForEach-Object { Quote-Argument -Value $_ }) -join ' '
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $QpdfPath
        $startInfo.Arguments = $argsString
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        try {
            if (-not $process.Start()) { return $false }
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

# Komprimiert eine PDF-Datei mit Ghostscript: 200 DPI, JPEG q75, sRGB.
function Optimize-WithGhostscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $GhostscriptPath,
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf
    )

    $tempPath = Join-Path $Pdf.DirectoryName ('.{0}.{1}.gs.tmp.pdf' -f $Pdf.BaseName, [guid]::NewGuid().ToString('N'))
    try {
        $gsArgList = @(
            '-dBATCH', '-dNOPAUSE', '-dQUIET',
            '-sDEVICE=pdfwrite',
            '-dDownsampleColorImages=true',
            '-dDownsampleGrayImages=true',
            '-dDownsampleMonoImages=true',
            '-dColorImageResolution=200',
            '-dGrayImageResolution=200',
            '-dMonoImageResolution=200',
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
        $argsString = ($gsArgList | ForEach-Object { Quote-Argument -Value $_ }) -join ' '
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

# --- Hauptverarbeitung ----------------------------------------------------

function Invoke-PdfProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string] $Language,
        [Parameter(Mandatory)][int] $Quality,
        [Parameter(Mandatory)][int] $Dpi,
        [Parameter(Mandatory)][bool] $Deskew,
        [Parameter(Mandatory)][bool] $RotatePages,
        [Parameter(Mandatory)][bool] $UseQpdf,
        [Parameter(Mandatory)][bool] $UseGhostscript,
        [string] $QpdfPath,
        [string] $GhostscriptPath
    )

    $tempPath = Join-Path $Pdf.DirectoryName ('.{0}.{1}.tmp.pdf' -f $Pdf.BaseName, [guid]::NewGuid().ToString('N'))
    $originalSize = $Pdf.Length
    $resultSize = [long]0

    try {
        Write-Host ('Schritt 1/2: OCRmyPDF (OCR + JPEG q{0} + Deskew {1})...' -f $Quality, $Deskew)

        # OCRmyPDF-Aufruf: Argumentliste über Quote-Argument zitieren,
        # damit Pfade mit Leerzeichen korrekt übergeben werden.
        $ocrArgsList = @(
            '-m', 'ocrmypdf',
            '--skip-text',
            '--optimize', '1',
            '--pdfa-image-compression', 'jpeg',
            '--jpeg-quality', "$Quality",
            '--image-dpi', "$Dpi",
            '--language', $Language
        )
        if ($Deskew) { $ocrArgsList += @('--deskew') }
        if ($RotatePages) { $ocrArgsList += @('--rotate-pages') }
        $ocrArgsList += @('--', $Pdf.FullName, $tempPath)

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $PythonPath
        $startInfo.Arguments = ($ocrArgsList | ForEach-Object { Quote-Argument -Value $_ }) -join ' '
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $false
        # OCRmyPDF-Fortschrittsbalken und Statusmeldungen sollen direkt
        # auf der Konsole erscheinen (Live-Ausgabe, wird nicht gefiltert).
        $startInfo.RedirectStandardOutput = $false
        $startInfo.RedirectStandardError = $false

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        try {
            if (-not $process.Start()) { throw 'OCRmyPDF konnte nicht gestartet werden.' }
            $process.WaitForExit()
            if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $tempPath)) {
                throw "OCRmyPDF fehlgeschlagen (Exitcode $($process.ExitCode))."
            }
        }
        finally { $process.Dispose() }

        $currentItem = Get-Item -LiteralPath $tempPath

        if ($UseQpdf -and $QpdfPath) {
            if (Optimize-WithQpdf -QpdfPath $QpdfPath -Pdf $currentItem) {
                $currentItem = Get-Item -LiteralPath $currentItem.FullName
            }
        }
        if ($UseGhostscript -and $GhostscriptPath) {
            Write-Host ('Schritt 2/2: Ghostscript-Optimierung (200 DPI)...')
            if (Optimize-WithGhostscript -GhostscriptPath $GhostscriptPath -Pdf $currentItem) {
                $currentItem = Get-Item -LiteralPath $currentItem.FullName
            }
        }

        $originalHash = Get-FileSha256 -Path $Pdf.FullName
        $resultHash = Get-FileSha256 -Path $currentItem.FullName
        if ($originalHash -eq $resultHash) {
            Write-Host 'Ergebnis ist identisch zum Original; Original bleibt unverändert.' -ForegroundColor Yellow
            return [pscustomobject]@{ Success = $false; OriginalBytes = [long]$originalSize; ResultBytes = [long]0 }
        }

        $resultSize = $currentItem.Length
        if ($resultSize -ge $originalSize) {
            Write-Host 'Ergebnis ist nicht kleiner; Original bleibt unverändert.' -ForegroundColor Yellow
            return [pscustomobject]@{ Success = $false; OriginalBytes = [long]$originalSize; ResultBytes = [long]$resultSize }
        }

        $backupPath = Join-Path $Pdf.DirectoryName ($Pdf.BaseName + '_orig' + $Pdf.Extension)
        if (-not (Test-Path -LiteralPath $backupPath)) {
            Copy-Item -LiteralPath $Pdf.FullName -Destination $backupPath
        }
        Move-Item -LiteralPath $currentItem.FullName -Destination $Pdf.FullName -Force

        $savedMb = ($originalSize - $resultSize) / 1MB
        $savedPct = if ($originalSize -gt 0) { (1 - ($resultSize / $originalSize)) * 100 } else { 0 }
        Write-Host ('Ergebnis: {0:N2} MB -> {1:N2} MB (gespart: {2:N2} MB / {3:N1} %)' -f ($originalSize/1MB), ($resultSize/1MB), $savedMb, $savedPct) -ForegroundColor Green
        Write-Host ('Gespeichert: {0}' -f $Pdf.FullName)
        return [pscustomobject]@{ Success = $true; OriginalBytes = [long]$originalSize; ResultBytes = [long]$resultSize }
    }
    catch {
        Write-Warning ("Fehler bei '{0}': {1}" -f $Pdf.Name, $_.Exception.Message)
        return [pscustomobject]@{ Success = $false; OriginalBytes = [long]$originalSize; ResultBytes = [long]$resultSize }
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- Hauptprogramm --------------------------------------------------------

# Prüfe vor der Verarbeitung alle erforderlichen Programme und Module,
# damit der Anwender alle Installationshinweise auf einmal erhält.
$dependencyCheck = Get-MissingDependency
if ($dependencyCheck.Missing.Count -gt 0) {
    Write-Host "`nFehlende Abhängigkeiten:" -ForegroundColor Yellow
    $dependencyCheck.Missing | ForEach-Object { Write-Host "  - $_" }
    Write-Host "`nBitte öffne eine neue PowerShell-Sitzung als Administrator und installiere:"
    Write-Host '  choco install python tesseract -y'
    Write-Host '  py -m pip install --user ocrmypdf'
    Write-Host "`nDanach starte dieses Skript erneut in einer normalen PowerShell."
    exit 1
}

# Tesseract-Sprachen ermitteln.
$tesseractPath = Get-ExecutablePath -Name 'tesseract'
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $tesseractPath
$startInfo.Arguments = '--list-langs'
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
$installedLanguages = @()
try {
    if (-not $process.Start()) { throw 'Tesseract konnte nicht gestartet werden.' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0) { throw "Tesseract --list-langs fehlgeschlagen: $stderr" }
    $installedLanguages = @($stdout -split '\r?\n' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and $_ -notmatch '^List of available languages' })
}
finally { $process.Dispose() }
if ($installedLanguages.Count -eq 0) {
    Write-Error 'Tesseract meldet keine installierten Sprachdaten.'
    exit 1
}

# Sprache wählen.
if (-not [string]::IsNullOrWhiteSpace($Language)) { $languageSelection = $Language.Trim() }
else { $languageSelection = $script:DefaultLanguage }

$requestedLanguages = @($languageSelection -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$missingRequired = @($script:RequiredLanguages | Where-Object { $requestedLanguages -notcontains $_ })
if ($missingRequired.Count -gt 0) {
    Write-Error ("Erforderliche Sprachen fehlen: {0}. Verfügbar: {1}" -f ($missingRequired -join ', '), ($installedLanguages -join ', '))
    exit 1
}
$droppedLanguages = @($requestedLanguages | Where-Object { $installedLanguages -notcontains $_ })
if ($droppedLanguages.Count -gt 0) {
    Write-Host ("Nicht installierte Sprachen werden ignoriert: {0}" -f ($droppedLanguages -join ', ')) -ForegroundColor DarkYellow
    $requestedLanguages = @($requestedLanguages | Where-Object { $installedLanguages -contains $_ })
}
if ($requestedLanguages.Count -eq 0) {
    Write-Error 'Nach Bereinigung sind keine gültigen OCR-Sprachen übrig.'
    exit 1
}
$languageSelection = $requestedLanguages -join '+'

# PDFs auflisten.
try { $pdfFiles = @(Get-PdfInputFile -Path $InputPath) }
catch { Write-Error $_.Exception.Message; exit 1 }
if ($pdfFiles.Count -eq 0) { Write-Host 'Keine PDFs gefunden.'; exit 0 }

# Kopfzeile.
Write-Host ''
Write-Host '=== PDF-Toolbox: Verarbeitung gestartet ===' -ForegroundColor Cyan
Write-Host ('Anzahl Dateien: {0}' -f $pdfFiles.Count)
Write-Host ('Sprachen: {0}' -f $languageSelection)
Write-Host ('JPEG-Qualität: {0}' -f $JpegQuality)
Write-Host ('Ghostscript-DPI: 200 (nicht unter 200 DPI)')
Write-Host ('Deskew: {0}' -f $Deskew)
Write-Host ('Ghostscript-Optimierung: {0}' -f $UseGhostscript)

# Verarbeitung.
$results = @()
for ($i = 0; $i -lt $pdfFiles.Count; $i++) {
    $pdf = $pdfFiles[$i]
    Write-Host ''
    Write-Host ('--- Datei {0}/{1}: {2} ---' -f ($i+1), $pdfFiles.Count, $pdf.Name) -ForegroundColor Cyan
    $r = Invoke-PdfProcessing -Pdf $pdf -PythonPath $dependencyCheck.PythonPath `
        -Language $languageSelection -Quality $JpegQuality -Dpi $ImageDpi `
        -Deskew $Deskew -RotatePages $RotatePages `
        -UseQpdf $UseQpdf -UseGhostscript $UseGhostscript `
        -QpdfPath $dependencyCheck.QpdfPath `
        -GhostscriptPath $dependencyCheck.GhostscriptPath
    if ($null -ne $r) { $results += $r }
}

# Zusammenfassung.
$successResults = @($results | Where-Object { $_.Success })
$successCount = $successResults.Count
$failureCount = @($results | Where-Object { -not $_.Success }).Count
$sumOriginal = [long](($results | ForEach-Object { [long]$_.OriginalBytes }) | Measure-Object -Sum).Sum
$sumResult = [long](($successResults | ForEach-Object { [long]$_.ResultBytes }) | Measure-Object -Sum).Sum
$savedMb = ($sumOriginal - $sumResult) / 1MB
$savedPct = if ($sumOriginal -gt 0) { (1 - ($sumResult / $sumOriginal)) * 100 } else { 0 }

Write-Host ''
Write-Host '=== Zusammenfassung ===' -ForegroundColor Cyan
Write-Host ('Erfolgreich: {0}, Fehlgeschlagen: {1}' -f $successCount, $failureCount)
Write-Host ('Original gesamt: {0:N2} MB' -f ($sumOriginal/1MB))
Write-Host ('Ergebnis gesamt: {0:N2} MB' -f ($sumResult/1MB))
Write-Host ('Gesamteinsparung: {0:N2} MB ({1:N1} %)' -f $savedMb, $savedPct)
Write-Host 'Sicherungskopien mit dem Suffix _orig liegen neben den Originalen.'
