<#
.SYNOPSIS
    Optimiert PDFs, begradigt schiefe Scan-Seiten und ergänzt eine OCR-Textebene.

.DESCRIPTION
    Verarbeitet eine einzelne PDF-Datei oder alle PDF-Dateien in einem angegebenen Ordner
    einschließlich seiner Unterordner. Nach erfolgreicher OCR wird die Eingabedatei überschrieben.
    Das bisherige Original wird standardmäßig als <Name>_orig.pdf gesichert.
    Mit -Replace wird die Eingabedatei ohne Sicherung überschrieben.

    VERARBEITUNG IN ZWEI STUFEN:
      1. OCRmyPDF: OCR-Textebene ergänzen, schiefe Seiten begradigen. Die Ausgabe erfolgt
         als normales PDF (Version 1.5), nicht als PDF/A-Archiv.
      2. Ghostscript (optional): Bilder auf die Zielauflösung herunterrechnen und als JPEG
         einbetten. Diese Stufe läuft nur, wenn eine Zielauflösung explizit über den
         Parameter -GhostscriptDpi vorgegeben wird (z. B. -GhostscriptDpi 150). Ohne
         diese Angabe bleibt das OCR-Ergebnis unverändert. Das Zwischenergebnis wird nur
         ersetzt, wenn die Ghostscript-Stufe es kleiner macht.

    BEIGRADIGUNG:
      - Schiefe Scan-Seiten werden automatisch begradigt (`--deskew`, standardmäßig aktiv).
      - Verdrehte Seiten (90°, 180°, 270°) werden standardmäßig nicht korrigiert.
        `-RotatePages` aktiviert die Erkennung mit einem OCRmyPDF-Konfidenzschwellwert
        von 5, damit auch Erkennungen mit geringer Konfidenz berücksichtigt werden.

    SPRACHEN:
      Standardfolge ist 'deu+eng+fra+ita+spa'. Deutsch (deu) und Englisch (eng) sind
      Pflicht: Fehlt eine der beiden Sprachdateien, stoppt das Skript mit einem Hinweis.
      Alle weiteren Sprachen sind optional: Fehlt eine, wird sie stillschweigend aus der
      Sprachfolge entfernt, ohne den Lauf zu unterbrechen. Es wird keine interaktive
      Sprachabfrage gestellt.

    ERGEBNISPRÜFUNG:
      Ein Lauf gilt nur dann als fehlgeschlagen, wenn OCRmyPDF tatsächlich fehlschlägt oder
      das Ergebnis byte-identisch (hash-gleich) zum Original ist, d. h. keine Veränderung
      stattgefunden hat. Ein größeres, aber inhaltlich verändertes Ergebnis wird als
      Erfolg gewertet und ersetzt die Eingabedatei.

    Das Skript selbst benötigt keine Administratorrechte und installiert keine Software.
    Fehlende Programme meldet es mit Installationshinweisen.

    Ausgabe: OCRmyPDF schreibt Fortschrittsbalken und Statusmeldungen direkt auf die
    Konsole (Live-Ausgabe, wird nicht gefiltert).

.PARAMETER Language
    OCR-Sprachen als mit '+' kombinierte Tesseract-Codes, z. B. 'deu+eng'.
    Vorgabe ist die Standardfolge 'deu+eng+fra+ita+spa' (Deutsch, Englisch, Französisch,
    Italienisch, Spanisch, in dieser Reihenfolge). deu und eng sind Pflicht, alle
    weiteren Sprachen werden bei Fehlen stillschweigend entfernt.

.PARAMETER InputPath
    Optionaler Pfad zu einer PDF-Datei oder einem Ordner mit PDF-Dateien.
    Ohne Angabe wird interaktiv danach gefragt.

.PARAMETER JpegQuality
    JPEG-Qualität für die eingebetteten Scan-Bilder (1-100).
    Vorgabe ist 75: guter Kompromiss aus Dateigröße und Lesbarkeit.

.PARAMETER GhostscriptDpi
    Zielauflösung der Ghostscript-Downsampling-Stufe in DPI (50-1200).
    Standard ist 0 = Stufe deaktiviert. Die Ghostscript-Komprimierung läuft nur, wenn
    hier explizit ein Wert vorgegeben wird, z. B. -GhostscriptDpi 150.

.PARAMETER NoDeskew
    Deaktiviert die standardmäßig aktive Begradigung schiefer Scan-Seiten.

.PARAMETER RotatePages
    Legt fest, ob verdrehte Seiten (90°, 180°, 270°) automatisch korrigiert werden sollen
    (Standard: $false). Bei Aktivierung wird ein Konfidenzschwellwert von 5 verwendet.

.PARAMETER NoGhostscript
    Deaktiviert Ghostscript als nachgelagerte Optimierungsstufe. Standardmäßig darf
    Ghostscript verwendet werden; es läuft nur in Kombination mit -GhostscriptDpi > 0.

.PARAMETER Replace
    Überschreibt die Eingabedatei ohne Sicherung. Standardmäßig wird das Original
    nach erfolgreicher Verarbeitung als <Name>_orig.pdf gesichert.

.EXAMPLE
    .\Invoke-PdfOcr.ps1
    Interaktiver Start mit der Standard-Sprachfolge deu+eng+fra+ita+spa, JPEG-Qualität 75,
    automatischer Begradigung schiefer Seiten. Das Original wird nach erfolgreicher
    Verarbeitung als _orig-Datei gesichert.

.EXAMPLE
    .\Invoke-PdfOcr.ps1 -InputPath 'C:\PDFs' -RotatePages -GhostscriptDpi 150
    Verarbeitet alle PDFs in C:\PDFs; Ghostscript rechnet die Bilder anschließend auf
    150 DPI herunter und komprimiert sie als JPEG. Die Originale bleiben als _orig-Dateien
    erhalten und die automatische Seitendrehung wird aktiviert.

.EXAMPLE
    .\Invoke-PdfOcr.ps1 -InputPath 'C:\PDFs' -Replace
    Verarbeitet alle PDFs in C:\PDFs und überschreibt die Originale ohne Sicherung.

.NOTES
    Abhängigkeiten:
      - Python
      - OCRmyPDF (Python-Modul)
      - Tesseract
      - Ghostscript (nur erforderlich bei -GhostscriptDpi > 0)

    Beispielinstallation aus einer PowerShell mit Administratorrechten:
      choco install python tesseract ghostscript -y
      py -m pip install --user ocrmypdf

    Tesseract-Sprachdaten (.traineddata) werden nicht mitinstalliert. Fehlen sie, weist
    das Skript auf https://github.com/tesseract-ocr/tessdata_best hin und nennt den
    lokalen tessdata-Ordner, in den die Dateien abgelegt werden müssen.

    TECHNISCHE HINWEISE:
      - Die Ausgabe ist ein normales PDF in Version 1.5 (`--output-type pdf` bei
        OCRmyPDF, `-dCompatibilityLevel=1.5` bei Ghostscript), kein PDF/A-Archiv.
      - `--optimize 1` statt `--optimize 3`: Stufe 3 würde eine jbig2-Warnung ausgeben,
        da jbig2 bewusst nicht installiert wird. Die starke Komprimierung übernimmt
        optional die Ghostscript-Stufe.
      - `--image-dpi` wird bei PDF-Eingaben von OCRmyPDF ignoriert und deshalb nicht
        übergeben; die Auflösung steuert ausschließlich die Ghostscript-Stufe.
      - Die Datei ist als UTF-8 mit BOM gespeichert; ohne BOM liest Windows PowerShell
        5.1 sie als ANSI und Umlaute in den Ausgaben werden falsch dargestellt.
#>

[CmdletBinding()]
param(
    # Abweichende Sprachfolge, z. B. 'deu+eng'. Leer = Standardfolge deu+eng+fra+ita+spa.
    [string] $Language,

    # Optionaler Pfad zu einer PDF-Datei oder einem Ordner mit PDF-Dateien.
    [string] $InputPath,

    # JPEG-Qualität für eingebettete Scan-Bilder (1-100). Vorgabe 75.
    [ValidateRange(1, 100)]
    [int] $JpegQuality = 75,

    # Zielauflösung der Ghostscript-Downsampling-Stufe in DPI.
    # Standard 0 = Stufe deaktiviert; Komprimierung läuft nur bei expliziter Vorgabe.
    [ValidateRange(0, 1200)]
    [int] $GhostscriptDpi = 0,

    # Begradigung schiefer Scan-Seiten deaktivieren (Standard: aktiv).
    [switch] $NoDeskew,

    # Automatische Drehkorrektur für 90°/180°/270°-Verdrehungen (Standard false).
    [switch] $RotatePages,

    # Ghostscript als nachgelagerte Optimierungsstufe deaktivieren (Standard false).
    # Wirksam nur in Kombination mit -GhostscriptDpi > 0.
    [switch] $NoGhostscript,

    # Eingabedatei ohne Sicherung überschreiben (standardmäßig wird _orig angelegt).
    [switch] $Replace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Standard-Sprachfolge für die OCR: Deutsch, Englisch, Französisch,
# Italienisch, Spanisch - in dieser Reihenfolge.
$script:DefaultLanguage = 'deu+eng+fra+ita+spa'

# Pflichtsprachen: Ohne deu oder eng stoppt das Skript mit einem Hinweis.
$script:RequiredLanguages = @('deu', 'eng')

# Quelle für Tesseract-Sprachdaten (.traineddata), die der Benutzer manuell
# in den tessdata-Ordner herunterladen und ablegen muss.
$script:TessdataUrl = 'https://github.com/tesseract-ocr/tessdata_best'

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
    # Liefert den vollständigen Pfad eines Programms aus dem PATH oder $null.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) { return $null }
    return $command.Source
}

function Test-PythonModule {
    # Prüft, ob ein Python-Modul importierbar ist, ohne eine Shell zu öffnen.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string] $ModuleName
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $PythonPath
    $startInfo.Arguments = "-c `"import $ModuleName`""
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { return $false }
        # Beide Streams asynchron lesen, damit die Pipe nicht blockiert.
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
    # Prüft alle erforderlichen Programme und Python-Module und liefert
    # deren Pfade bzw. eine Liste der fehlenden Abhängigkeiten.
    # Ghostscript ist optional: Ein Fehlen wird gemeldet, blockiert den Lauf
    # aber nicht (die Ghostscript-Stufe wird dann übersprungen).
    [CmdletBinding()]
    param([bool] $NoGhostscript = $false)

    $missing = [System.Collections.Generic.List[string]]::new()
    $optionalMissing = [System.Collections.Generic.List[string]]::new()
    $pythonPath = Get-ExecutablePath -Name 'py'
    if (-not $pythonPath) { $pythonPath = Get-ExecutablePath -Name 'python' }
    if (-not $pythonPath) { $missing.Add('Python (py.exe oder python.exe)') }
    if (-not (Get-ExecutablePath -Name 'tesseract')) { $missing.Add('Tesseract') }

    # Ghostscript ist die optionale Optimierungsstufe nach OCRmyPDF.
    $ghostscriptPath = $null
    if (-not $NoGhostscript) {
        $ghostscriptPath = Get-ExecutablePath -Name 'gswin64c'
        if (-not $ghostscriptPath) { $ghostscriptPath = Get-ExecutablePath -Name 'gswin32c' }
        if (-not $ghostscriptPath) { $ghostscriptPath = Get-ExecutablePath -Name 'gs' }
        if (-not $ghostscriptPath) { $optionalMissing.Add('Ghostscript (nur für -GhostscriptDpi erforderlich)') }
    }

    # pngquant ist für die OCRmyPDF-Optimierung optional; ein Fehlen darf den
    # Lauf nicht blockieren. jbig2 wird bewusst nicht verwendet (nur für
    # Schwarz-Weiß-Bilder relevant, hier JPEG-Kompression im Einsatz).
    if ($pythonPath -and -not (Test-PythonModule -PythonPath $pythonPath -ModuleName 'ocrmypdf')) {
        $missing.Add('OCRmyPDF (Python-Modul)')
    }

    [pscustomobject]@{
        PythonPath      = $pythonPath
        GhostscriptPath = $ghostscriptPath
        Missing         = $missing
        OptionalMissing = $optionalMissing
    }
}

function Invoke-Tesseract {
    # Führt tesseract mit den angegebenen Argumenten aus und liefert
    # Exitcode, Stdout und Stderr als Objekt. Direkter Prozessstart mit
    # umgeleiteten Streams, damit Tesseract-Fehler nicht durch PowerShells
    # NativeCommand-Verhalten als Terminierungsfehler fehlinterpretiert werden.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $TesseractPath,
        [Parameter(Mandatory)][string] $Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $TesseractPath
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Tesseract konnte nicht gestartet werden.' }
        # Asynchron lesen, damit große Ausgaben die Pipe nicht blockieren.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdoutTask.GetAwaiter().GetResult()
            StdErr   = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally { $process.Dispose() }
}

function Get-TesseractLanguages {
    # Ermittelt über `tesseract --list-langs` die installierten Sprachen
    # und den verwendeten tessdata-Ordner.
    # Rückgabe: Objekt mit Languages (Sprachcodes) und TessdataPath.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $TesseractPath)

    $result = Invoke-Tesseract -TesseractPath $TesseractPath -Arguments '--list-langs'
    if ($result.ExitCode -ne 0) {
        throw "Tesseract --list-langs fehlgeschlagen: $($result.StdErr)"
    }

    # Die Kopfzeile nennt den tessdata-Ordner in Anführungszeichen, z. B.:
    # List of available languages in "C:\Program Files\Tesseract-OCR\tessdata" (5):
    $tessdataPath = $null
    if ($result.StdOut -match 'List of available languages in "([^"]+)"') {
        $tessdataPath = $Matches[1]
    }
    if (-not $tessdataPath) {
        # Fallback: tessdata liegt üblicherweise neben der tesseract.exe.
        $tessdataPath = Join-Path -Path (Split-Path -Parent $TesseractPath) -ChildPath 'tessdata'
    }

    # Kopfzeile verwerfen, nur die Sprachcodes behalten.
    $languages = @($result.StdOut -split '\r?\n' | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and $_ -notmatch '^List of available languages' })

    [pscustomobject]@{ Languages = $languages; TessdataPath = $tessdataPath }
}

function Show-LanguageDownloadHint {
    # Hinweis bei fehlenden Pflicht-Sprachdaten (deu/eng): Verweist auf das
    # tessdata_best-Repository und nennt den lokalen Ordner, in den die
    # .traineddata-Dateien abgelegt werden müssen.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $MissingLanguages,
        [Parameter(Mandatory)][string] $TessdataPath
    )

    Write-Host ''
    Write-Host "Fehlende Pflicht-Sprachdaten: $($MissingLanguages -join ', ')."
    Write-Host "Lade die gewünschten .traineddata-Dateien von $script:TessdataUrl herunter"
    Write-Host "und lege sie in den lokalen tessdata-Ordner: $TessdataPath"
}

function Get-PdfInputFile {
    # Ermittelt die zu verarbeitenden PDF-Dateien aus einem Datei- oder
    # Ordnerpfad. Ohne Angabe wird interaktiv danach gefragt.
    [CmdletBinding()]
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Host ''
        Write-Host 'Mögliche Parameter:' -ForegroundColor Cyan
        Write-Host '  -InputPath <Pfad>       PDF-Datei oder Ordner; ohne Angabe erscheint diese Abfrage.'
        Write-Host '  -Language <Sprachen>    OCR-Sprachen, z. B. deu+eng (Standard: deu+eng+fra+ita+spa).'
        Write-Host '  -JpegQuality <1-100>   JPEG-Qualität (Standard: 75).'
        Write-Host '  -GhostscriptDpi <DPI>  Optionale Ghostscript-Auflösung (Standard: deaktiviert).'
        Write-Host '  -NoDeskew              Schräglagenkorrektur deaktivieren (Standard: aktiv).'
        Write-Host '  -RotatePages           Verdrehte Seiten automatisch korrigieren (Standard: aus).'
        Write-Host '  -NoGhostscript         Ghostscript-Komprimierung deaktivieren (Standard: erlaubt).'
        Write-Host '  -Replace               Original ohne _orig-Sicherung überschreiben.'
        Write-Host 'Mit Strg+C kannst du die Eingabe abbrechen.' -ForegroundColor Yellow
        $Path = Read-Host 'Pfad zu einer PDF-Datei oder einem Ordner mit PDFs'
    }
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Es wurde kein Pfad eingegeben.' }
    $Path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (-not (Test-Path -LiteralPath $Path)) { throw "Pfad nicht gefunden: $Path" }
    $item = Get-Item -LiteralPath $Path
    $script:InputDirectoryPath = if ($item.PSIsContainer) {
        $item.FullName
    }
    else {
        $item.DirectoryName
    }
    if ($item.PSIsContainer) {
        # _orig-Sicherungen bei der rekursiven Suche nicht erneut verarbeiten.
        return @(Get-ChildItem -LiteralPath $item.FullName -File -Filter '*.pdf' -Recurse |
            Where-Object { $_.BaseName -notmatch '_orig$' })
    }
    if ($item.Extension -ine '.pdf') { throw 'Die ausgewählte Datei hat keine .pdf-Endung.' }
    return @($item)
}

function Get-FileSha256 {
    # Berechnet den SHA-256-Hash einer Datei und liefert ihn als Hex-String.
    # Wird verwendet, um ein unverändertes Ergebnis (hash-gleich zum Original)
    # als Fehlschlag zu erkennen.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $hashBytes = $sha256.ComputeHash($stream)
            return [System.BitConverter]::ToString($hashBytes).Replace('-', '')
        }
        finally { $stream.Dispose() }
    }
    finally { $sha256.Dispose() }
}

# Komprimiert eine PDF-Datei mit Ghostscript: Zielauflösung (DPI), JPEG q75,
# Ausgabe als normales PDF Version 1.5. Ersetzt die Eingabedatei nur, wenn das
# Ergebnis kleiner ist; anderenfalls bleibt die Eingabe unverändert.
# Rückgabe: $true bei Verkleinerung.
function Optimize-WithGhostscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $GhostscriptPath,
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][int] $Dpi
    )

    $tempPath = Join-Path $Pdf.DirectoryName ('.{0}.{1}.gs.tmp.pdf' -f $Pdf.BaseName, [guid]::NewGuid().ToString('N'))
    try {
        # Explizite Downsampling-Parameter statt -dPDFSETTINGS: garantiert die
        # Zielauflösung für Farb-, Graustufen- und Schwarz-Weiß-Bilder, eingebettet als JPEG.
        # -dCompatibilityLevel=1.5 spezifiziert die PDF-Version des Ergebnisses (1.5).
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
            # Streams asynchron lesen, damit die Pipes nicht blockieren.
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
    # Verarbeitet eine einzelne PDF-Datei in zwei Stufen:
    #   1. OCRmyPDF: OCR-Textebene ergänzen, optimieren und schiefe Seiten begradigen.
    #      Ausgabe als normales PDF Version 1.5 (--output-type pdf), kein PDF/A-Archiv.
    #   2. Ghostscript (optional): Bilder auf die Zielauflösung nachkomprimieren.
    #      Läuft nur, wenn explizit eine DPI-Zahl übergeben wurde ($GhostscriptDpi > 0).
    # Das Ergebnis ersetzt die Eingabe; standardmäßig wird sie vorher als _orig.pdf gesichert.
    # Ein Lauf gilt nur als Fehlschlag, wenn OCRmyPDF fehlschlägt oder das Ergebnis
    # hash-gleich zum Original ist (keine Änderung).
    # `--optimize 1` statt 3: Stufe 3 erzeugt eine jbig2-Warnung, die wir nicht
    # benötigen (jbig2 wird bewusst nicht installiert).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string] $Language,
        [Parameter(Mandatory)][int] $Quality,
        [Parameter(Mandatory)][int] $GhostscriptDpi,
        [Parameter(Mandatory)][bool] $NoDeskew,
        [Parameter(Mandatory)][bool] $RotatePages,
        [Parameter(Mandatory)][bool] $NoGhostscript,
        [Parameter(Mandatory)][bool] $Replace,
        [string] $GhostscriptPath
    )

    # Temporäre Datei neben der Eingabe, damit Verschieben auf demselben Laufwerk bleibt.
    $tempPath = Join-Path $Pdf.DirectoryName ('.{0}.{1}.tmp.pdf' -f $Pdf.BaseName, [guid]::NewGuid().ToString('N'))
    $originalPath = Join-Path $Pdf.DirectoryName ($Pdf.BaseName + '_orig' + $Pdf.Extension)
    $replaceBackupPath = $tempPath + '.bak'
    try {
        Write-Host "Bearbeite: $($Pdf.Name)"
        # Normales PDF (Version 1.5) statt PDF/A-Archiv als Ergebnis.
        # Kein --image-dpi: wird bei PDF-Eingaben ignoriert und gemeldet; die
        # Auflösung steuert die Ghostscript-Stufe.
        # --optimize 1 statt 3: vermeidet die jbig2-Warnung (jbig2 wird nicht installiert).
        $ocrArgs = @(
            '--skip-text',
            '--output-type', 'pdf',
            '--optimize', '1',
            '--jpeg-quality', $Quality,
            '--language', $Language
        )
        if (-not $NoDeskew) { $ocrArgs += '--deskew' }
        if ($RotatePages) {
            # Die niedrigere Schwelle lässt auch Rotationen mit geringer Tesseract-Konfidenz zu.
            $ocrArgs += @('--rotate-pages', '--rotate-pages-threshold', '5')
        }

        # Live-Ausgabe: OCRmyPDF läuft ohne Umleitung, Fortschrittsbalken und
        # Statusmeldungen erscheinen direkt auf der Konsole.
        & $PythonPath -m ocrmypdf @ocrArgs -- $Pdf.FullName $tempPath
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempPath)) {
            throw "OCRmyPDF fehlgeschlagen (Exitcode $LASTEXITCODE)."
        }

        # Nachgelagerte Ghostscript-Optimierung: läuft nur, wenn explizit eine
        # Zielauflösung vorgegeben wurde (GhostscriptDpi > 0) und Ghostscript
        # verfügbar ist. Nur bei Verkleinerung wird das Ergebnis übernommen.
        if (-not $NoGhostscript -and $GhostscriptDpi -gt 0 -and $GhostscriptPath) {
            $gsResult = Get-Item -LiteralPath $tempPath
            Optimize-WithGhostscript -GhostscriptPath $GhostscriptPath -Pdf $gsResult -Dpi $GhostscriptDpi | Out-Null
        }

        $originalSize = (Get-Item -LiteralPath $Pdf.FullName).Length
        $resultSize = (Get-Item -LiteralPath $tempPath).Length

        # Hash-Vergleich: Ein hash-gleiches Ergebnis bedeutet, dass keine
        # inhaltliche Veränderung stattgefunden hat - dann ist der Lauf ein
        # Fehlschlag. Ein größeres, aber verändertes Ergebnis ist ein Erfolg.
        $originalHash = Get-FileSha256 -Path $Pdf.FullName
        $resultHash = Get-FileSha256 -Path $tempPath
        if ($originalHash -eq $resultHash) {
            Write-Host 'Ergebnis ist identisch zum Original (keine Änderung); Datei wird verworfen.' -ForegroundColor Yellow
            return [pscustomobject]@{ Success = $false; OriginalBytes = [long]$originalSize; ResultBytes = [long]0 }
        }

        # Erst nach erfolgreicher Verarbeitung und Hash-Prüfung atomar austauschen.
        if (-not $Replace) {
            if (Test-Path -LiteralPath $originalPath) {
                throw "Die Sicherungsdatei '$originalPath' existiert bereits; sie wird nicht überschrieben."
            }
            [System.IO.File]::Replace($tempPath, $Pdf.FullName, $originalPath)
            Write-Host "Original gesichert: $originalPath"
        }
        else {
            [System.IO.File]::Replace($tempPath, $Pdf.FullName, $replaceBackupPath)
        }
        if ($resultSize -lt $originalSize) {
            Write-Host ('Optimiert: {0:N1} MB -> {1:N1} MB' -f ($originalSize / 1MB), ($resultSize / 1MB)) -ForegroundColor Green
        }
        else {
            Write-Host ('Verarbeitet (größer als Original): {0:N1} MB -> {1:N1} MB' -f ($originalSize / 1MB), ($resultSize / 1MB)) -ForegroundColor Cyan
        }
        Write-Host "Gespeichert: $($Pdf.FullName)"
        return [pscustomobject]@{ Success = $true; OriginalBytes = [long]$originalSize; ResultBytes = [long]$resultSize }
    }
    catch {
        Write-Warning "Fehler bei '$($Pdf.Name)': $($_.Exception.Message)"
        return [pscustomobject]@{ Success = $false; OriginalBytes = [long]0; ResultBytes = [long]0 }
    }
    finally {
        # Temporäre Datei auch im Fehlerfall zuverlässig entfernen.
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $replaceBackupPath) {
            Remove-Item -LiteralPath $replaceBackupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- Hauptprogramm --------------------------------------------------------

# ASCII-Kopf: Kurzbeschreibung, was das Skript tut.
Write-Host ''
Write-Host '       .-------------------------------------------------------.' -ForegroundColor Cyan
Write-Host '       |  +------------------+                                 |' -ForegroundColor Cyan
Write-Host '       |  |   PDF  ->  OCR   |        P D F  -  O C R          |' -ForegroundColor Cyan
Write-Host '       |  | [##########]     |                                 |' -ForegroundColor Cyan
Write-Host '       |  | [__________] >>> |        SCAN  /  TEXT            |' -ForegroundColor Cyan
Write-Host '       |  +------------------+        DESKEW / OPTIMIZE        |' -ForegroundColor Cyan
Write-Host '       ''-------------------------------------------------------''' -ForegroundColor Cyan
Write-Host '  Fuegt PDFs OCR-Textebenen hinzu, begradigt Seiten und optimiert Dateien.' -ForegroundColor Cyan
if (-not $Replace) {
    Write-Host '  Originale werden als _orig-Dateien gesichert.' -ForegroundColor Cyan
}
else {
    Write-Host '  Originale werden ueberschrieben.' -ForegroundColor Cyan
}
Write-Host ''

# Prüfe vor der Verarbeitung alle erforderlichen Programme und Module,
# damit der Anwender alle Installationshinweise auf einmal erhält.
$dependencyCheck = Get-MissingDependency -NoGhostscript $NoGhostscript.IsPresent
if ($dependencyCheck.Missing.Count -gt 0) {
    Write-Host "`nFehlende Abhängigkeiten:" -ForegroundColor Yellow
    $dependencyCheck.Missing | ForEach-Object { Write-Host "  - $_" }
    Write-Host "`nBitte öffne eine neue PowerShell-Sitzung als Administrator und installiere:"
    Write-Host '  choco install python tesseract -y'
    Write-Host '  py -m pip install --user ocrmypdf'
    Write-Host "`nDanach starte dieses Skript erneut in einer normalen PowerShell."
    exit 1
}
if ($dependencyCheck.OptionalMissing.Count -gt 0) {
    Write-Host "`nOptionale Werkzeuge nicht gefunden (Optimierung wird eingeschränkt):" -ForegroundColor DarkYellow
    $dependencyCheck.OptionalMissing | ForEach-Object { Write-Host "  - $_" }
    Write-Host '  Installation (Admin-Shell): choco install ghostscript -y'
    Write-Host '  Danach eine neue PowerShell-Sitzung öffnen und das Skript erneut starten.'
    Write-Host ''
}

# --- Tesseract-Sprachen und tessdata-Ordner ermitteln -------------------------
$tesseractPath = Get-ExecutablePath -Name 'tesseract'
try {
    $tesseractInfo = Get-TesseractLanguages -TesseractPath $tesseractPath
}
catch {
    Write-Error "Tesseract-Sprachen konnten nicht ermittelt werden. Prüfe `"tesseract --list-langs`": $($_.Exception.Message)"
    exit 1
}
$installedLanguages = @($tesseractInfo.Languages)

# --- Eingabedateien ermitteln --------------------------------------------------
try { $pdfFiles = @(Get-PdfInputFile -Path $InputPath) }
catch { Write-Error $_.Exception.Message; exit 1 }
if ($pdfFiles.Count -eq 0) { Write-Host 'Keine PDFs gefunden.'; exit 0 }
$summaryPathSegments = @($script:InputDirectoryPath.TrimEnd('\') -split '[\\/]' | Where-Object { $_ })
$summaryPathTail = @($summaryPathSegments | Select-Object -Last 3)
$summaryPath = '.\' + ($summaryPathTail -join '\') + '\'

# --- Sprachfolge festlegen ------------------------------------------------------
# Vorgabe ist die Standardfolge Deutsch, Englisch, Französisch, Italienisch,
# Spanisch. Über -Language kann eine abweichende Sprachfolge vorgegeben werden;
# es wird keine interaktive Abfrage gestellt. deu und eng sind Pflicht und
# stoppen das Skript bei Fehlen; alle anderen fehlenden Sprachen werden
# stillschweigend aus der Sprachfolge entfernt.
if (-not [string]::IsNullOrWhiteSpace($Language)) {
    $languageSelection = $Language.Trim()
}
else {
    $languageSelection = $script:DefaultLanguage
}

# Reihenfolge der Eingabe bleibt erhalten und wird so an OCRmyPDF übergeben.
$requestedLanguages = @($languageSelection -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# Pflichtsprachen prüfen: Fehlt deu oder eng, Hinweis auf tessdata_best und Programmende.
$missingRequired = @($requestedLanguages | Where-Object { $script:RequiredLanguages -contains $_ -and $installedLanguages -notcontains $_ })
if ($missingRequired.Count -gt 0) {
    Show-LanguageDownloadHint -MissingLanguages $missingRequired -TessdataPath $tesseractInfo.TessdataPath
    exit 1
}

# Optionale Sprachen stillschweigend entfernen, falls nicht installiert.
$availableLanguages = @($requestedLanguages | Where-Object { $installedLanguages -contains $_ })
$droppedLanguages = @($requestedLanguages | Where-Object { $installedLanguages -notcontains $_ })
if ($droppedLanguages.Count -gt 0) {
    Write-Host "Hinweis: Folgende Sprachen nicht installiert und werden entfernt: $($droppedLanguages -join ', ')" -ForegroundColor DarkYellow
}
if ($availableLanguages.Count -eq 0) {
    Write-Error 'Keine der angeforderten Sprachen ist installiert.'
    exit 1
}
$languageSelection = $availableLanguages -join '+'

# Kopfzeile.
Write-Host ''
Write-Host '=== PDF-OCR: Verarbeitung gestartet ===' -ForegroundColor Cyan
Write-Host ('Anzahl Dateien: {0}' -f $pdfFiles.Count)
Write-Host ('Sprachen: {0}' -f $languageSelection)
Write-Host ('JPEG-Qualität: {0}' -f $JpegQuality)
if ($GhostscriptDpi -gt 0) {
    Write-Host ('Ghostscript-DPI: {0}' -f $GhostscriptDpi)
}
else {
    Write-Host 'Ghostscript-DPI: deaktiviert (Komprimierung nur mit -GhostscriptDpi)'
}
Write-Host ('Deskew: {0}' -f (-not $NoDeskew))
Write-Host ('Ausgabeformat: normales PDF (Version 1.5)')

# --- PDFs verarbeiten -----------------------------------------------------------
$results = @()
for ($i = 0; $i -lt $pdfFiles.Count; $i++) {
    $pdf = $pdfFiles[$i]
    Write-Host ''
    Write-Host ('--- Datei {0}/{1}: {2} ---' -f ($i + 1), $pdfFiles.Count, $pdf.Name) -ForegroundColor Cyan
    $r = Invoke-PdfProcessing -Pdf $pdf -PythonPath $dependencyCheck.PythonPath `
        -Language $languageSelection -Quality $JpegQuality -GhostscriptDpi $GhostscriptDpi `
        -NoDeskew $NoDeskew.IsPresent -RotatePages $RotatePages.IsPresent `
        -NoGhostscript $NoGhostscript.IsPresent -Replace $Replace.IsPresent `
        -GhostscriptPath $dependencyCheck.GhostscriptPath
    if ($null -ne $r) { $results += $r }
}

# --- Zusammenfassung -------------------------------------------------------------
$successResults = @($results | Where-Object { $_.Success })
$successCount = $successResults.Count
$failureCount = @($results | Where-Object { -not $_.Success }).Count
$sumOriginal = [long](($results | ForEach-Object { [long]$_.OriginalBytes }) | Measure-Object -Sum).Sum
$sumResult = [long](($successResults | ForEach-Object { [long]$_.ResultBytes }) | Measure-Object -Sum).Sum
$savedMb = ($sumOriginal - $sumResult) / 1MB
$savedPct = if ($sumOriginal -gt 0) { (1 - ($sumResult / $sumOriginal)) * 100 } else { 0 }

Write-Host ''
Write-Host '=== Zusammenfassung ===' -ForegroundColor Cyan
Write-Host "Pfad: $summaryPath"
Write-Host ('Erfolgreich: {0}, Fehlgeschlagen: {1}' -f $successCount, $failureCount)
if ($successCount -gt 0) {
    Write-Host ('Original gesamt: {0:N2} MB' -f ($sumOriginal / 1MB))
    Write-Host ('Ergebnis gesamt: {0:N2} MB' -f ($sumResult / 1MB))
    Write-Host ('Gesamteinsparung: {0:N2} MB ({1:N1} %)' -f $savedMb, $savedPct)
}
if (-not $Replace) {
    Write-Host 'Originale wurden als _orig-Dateien gesichert.'
}
else {
    Write-Host 'Originale wurden überschrieben.'
}
