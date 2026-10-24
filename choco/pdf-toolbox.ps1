<#
.SYNOPSIS
    Optimiert PDFs, begradigt schiefe Scan-Seiten und ergänzt eine OCR-Textebene.

.DESCRIPTION
    Verarbeitet eine einzelne PDF-Datei oder alle PDF-Dateien direkt in einem angegebenen
    Ordner (keine Unterordner). Das Original bleibt stets unverändert erhalten; das
    verarbeitete Ergebnis wird als neue Datei mit dem Suffix _ocr neben das Original gelegt.

    VERARBEITUNG IN ZWEI STUFEN:
      1. OCRmyPDF: OCR-Textebene ergänzen, schiefe Seiten begradigen und Bilder als
         JPEG (Qualität 75) einbetten (`--pdfa-image-compression jpeg`). Die Ausgabe
         erfolgt als PDF/A-2b.
      2. Ghostscript: Bilder auf 150 DPI herunterrechnen und als JPEG einbetten
         (`-dPDFSETTINGS=/ebook`). Diese Stufe ersetzt das Zwischenergebnis nur, wenn
         es dadurch kleiner wird.

    BEIGRADIGUNG:
      - Schiefe Scan-Seiten werden automatisch begradigt (`--deskew`, standardmäßig aktiv).
      - Verdrehte Seiten (90°, 180°, 270°) werden NICHT automatisch korrigiert
        (`--rotate-pages` ist standardmäßig deaktiviert und kann über den Parameter
        `-RotatePages` explizit aktiviert werden).

    SPRACHEN:
      Standardfolge ist 'deu+eng+fra+ita+spa'. Deutsch (deu) und Englisch (eng) sind
      Pflicht: Fehlt eine der beiden Sprachdateien, stoppt das Skript mit einem
      Download-Hinweis. Alle weiteren Sprachen sind optional: Fehlt eine, wird sie
      stillschweigend aus der Sprachfolge entfernt, ohne den Lauf zu unterbrechen.
      Es wird keine interaktive Sprachabfrage gestellt.

    ERGEBNISPRÜFUNG:
      Ein Lauf gilt nur dann als fehlgeschlagen, wenn OCRmyPDF tatsächlich fehlschlägt oder
      das Ergebnis byte-identisch (hash-gleich) zum Original ist, d. h. keine Veränderung
      stattgefunden hat. Ein größeres, aber inhaltlich verändertes Ergebnis wird als
      Erfolg gewertet und als _ocr-Datei abgelegt.

    Das Skript selbst benötigt keine Administratorrechte und installiert keine Software.
    Fehlende Programme meldet es mit Installationshinweisen. Fehlende Pflicht-Sprachdaten
    (deu/eng) werden mit einem Zweizeiler gemeldet, der den Benutzer auffordert, einen
    Download-Befehl in einer Admin-Shell auszuführen, um alle Sprachen herunterzuladen.

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

.PARAMETER ImageDpi
    Gewünschte Auflösung der eingebetteten Scan-Bilder in DPI (50-1200).
    Vorgabe ist 300. Hinweis: OCRmyPDF ignoriert --image-dpi bei PDF-Eingaben
    (gilt nur für Bilddateien); die tatsächliche Auflösungssteuerung bei PDFs
    übernimmt die Ghostscript-Stufe (150 DPI).

.PARAMETER Deskew
    Legt fest, ob schiefe Scan-Seiten begradigt werden sollen (Standard: $true).
    Bei aktivierter Begradigung wird `--deskew` an OCRmyPDF übergeben.

.PARAMETER RotatePages
    Legt fest, ob verdrehte Seiten (90°, 180°, 270°) automatisch korrigiert werden sollen
    (Standard: $false). Bei Aktivierung wird `--rotate-pages` an OCRmyPDF übergeben.

.PARAMETER UseGhostscript
    Legt fest, ob Ghostscript als nachgelagerte Optimierungsstufe verwendet werden soll
    (Standard: $true). Erfordert Ghostscript (gswin64c/gswin32c/gs) im PATH;
    ohne Ghostscript wird die Stufe übersprungen.

.EXAMPLE
    .\pdf-toolbox.ps1
    Interaktiver Start mit der Standard-Sprachfolge deu+eng+fra+ita+spa, JPEG-Qualität 75,
    automatischer Begradigung schiefer Seiten und deaktivierter automatischer
    Drehkorrektur. Ergebnisse werden als <Name>_ocr.pdf abgelegt.

.EXAMPLE
    .\pdf-toolbox.ps1 -InputPath 'C:\PDFs' -Language 'deu+eng' -JpegQuality 65 -Deskew:$true -RotatePages:$true
    Verarbeitet alle PDFs in C:\PDFs mit deutscher und englischer OCR, stärkerer JPEG-
    Kompression, automatischer Begradigung und automatischer Drehkorrektur.

.EXAMPLE
    .\pdf-toolbox.ps1 -InputPath 'C:\PDFs' -UseGhostscript:$false
    Deaktiviert die Ghostscript-Optimierungsstufe; nur OCRmyPDF wird angewendet.

.NOTES
    Abhängigkeiten:
      - Python
      - OCRmyPDF (Python-Modul)
      - Tesseract
      - Ghostscript (empfohlen für die stärkste Kompression)

    Beispielinstallation aus einer PowerShell mit Administratorrechten:
      choco install python tesseract ghostscript -y
      py -m pip install --user ocrmypdf

    Tesseract-Sprachdaten (.traineddata) werden nicht mitinstalliert.
    Quelle für alle Sprachen: https://github.com/tesseract-ocr/tessdata
    Fehlen deu oder eng, lädt der vom Skript ausgegebene Befehl in einer
    Admin-Shell alle Sprachen herunter. Danach `tesseract --list-langs` prüfen und eine
    neue PowerShell-Sitzung öffnen.

    TECHNISCHE HINWEISE:
      - `--optimize 1` statt `--optimize 3`: Stufe 3 würde eine jbig2-Warnung ausgeben,
        da jbig2 bewusst nicht installiert wird (nur für Schwarz-Weiß relevant; hier
        läuft JPEG-Kompression). Stufe 1 reicht, da Ghostscript die starke Kompression
        übernimmt.
      - `--output-type pdf` wird bewusst NICHT gesetzt, da OCRmyPDF die
        JPEG-Kompression (`--pdfa-image-compression`) nur bei `--output-type auto`
        oder `pdfa*` anwendet. Ohne `--output-type` greift die Kompression zuverlässig
        und die Ausgabe erfolgt als PDF/A-2b.
      - `--image-dpi` wird bei PDF-Eingaben von OCRmyPDF ignoriert; die Auflösung
        wird von der Ghostscript-Stufe gesteuert.

    WEITERE MÖGLICHKEITEN ZUR REDUZIERUNG DER DATEIGRÖSSE:
      - Niedrigere JPEG-Qualität: -JpegQuality 60 (noch gut lesbar, deutlich kleiner).
      - Graustufen statt Farbe: OCRmyPDF-Option `--grayscale` (spart zusätzlich, wenn die
        Dokumente keine Farbe benötigen).
      - Reines Schwarz-Weiß: OCRmyPDF-Option `--threshold` (stärkste Kompression, aber
        Verlust von Graustufen und Hintergrunddetails).
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

    # Gewünschte Auflösung der eingebetteten Scan-Bilder in DPI. Vorgabe 300.
    # Hinweis: Bei PDF-Eingaben ignoriert OCRmyPDF diesen Wert; die Ghostscript-Stufe
    # steuert die tatsächliche Auflösung (150 DPI).
    [ValidateRange(50, 1200)]
    [int] $ImageDpi = 300,

    # Begradigung schiefer Scan-Seiten aktivieren (Standard true).
    [bool] $Deskew = $true,

    # Automatische Drehkorrektur für 90°/180°/270°-Verdrehungen (Standard false).
    [bool] $RotatePages = $false,

    # Ghostscript als nachgelagerte Optimierungsstufe verwenden (Standard true).
    [bool] $UseGhostscript = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Standard-Sprachfolge für die OCR: Deutsch, Englisch, Französisch,
# Italienisch, Spanisch - in dieser Reihenfolge.
$script:DefaultLanguage = 'deu+eng+fra+ita+spa'

# Pflichtsprachen: Ohne deu oder eng stoppt das Skript mit Download-Hinweis.
$script:RequiredLanguages = @('deu', 'eng')

# Quelle der vollständigen Tesseract-Sprachdatensammlung (.traineddata).
$script:TessdataZipUrl = 'https://github.com/tesseract-ocr/tessdata/archive/refs/heads/main.zip'

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
    param()

    $missing = [System.Collections.Generic.List[string]]::new()
    $optionalMissing = [System.Collections.Generic.List[string]]::new()
    $pythonPath = Get-ExecutablePath -Name 'py'
    if (-not $pythonPath) { $pythonPath = Get-ExecutablePath -Name 'python' }
    if (-not $pythonPath) { $missing.Add('Python (py.exe oder python.exe)') }
    if (-not (Get-ExecutablePath -Name 'tesseract')) { $missing.Add('Tesseract') }

    # Ghostscript ist die empfohlene Optimierungsstufe nach OCRmyPDF.
    $ghostscriptPath = Get-ExecutablePath -Name 'gswin64c'
    if (-not $ghostscriptPath) { $ghostscriptPath = Get-ExecutablePath -Name 'gswin32c' }
    if (-not $ghostscriptPath) { $ghostscriptPath = Get-ExecutablePath -Name 'gs' }
    if (-not $ghostscriptPath) { $optionalMissing.Add('Ghostscript (empfohlen für stärkste Kompression)') }

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
    # Zweizeiler bei fehlenden Pflicht-Sprachdaten (deu/eng): Zeile 1 fordert den
    # Benutzer auf, den Download in einer Admin-Shell auszuführen, Zeile 2 ist der
    # Befehl, der alle Sprachen aus dem tessdata-Repository herunterlädt
    # und im tessdata-Ordner ablegt.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $MissingLanguages,
        [Parameter(Mandatory)][string] $TessdataPath
    )

    $downloadCommand = "Invoke-WebRequest '$script:TessdataZipUrl' -OutFile `$env:TEMP\tessdata.zip; " +
        "Expand-Archive `$env:TEMP\tessdata.zip `$env:TEMP\tessdata -Force; " +
        "Copy-Item `$env:TEMP\tessdata\tessdata-main\*.traineddata '$TessdataPath\' -Force"

    Write-Host ''
    Write-Host "Fehlende Pflicht-Sprachdaten: $($MissingLanguages -join ', '). Bitte öffne eine PowerShell als Administrator und führe folgenden Befehl aus, um alle Sprachen herunterzuladen:"
    Write-Host "  $downloadCommand"
}

function Get-PdfInputFile {
    # Ermittelt die zu verarbeitenden PDF-Dateien aus einem Datei- oder
    # Ordnerpfad. Ohne Angabe wird interaktiv danach gefragt.
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
        # Nur Dateien direkt im Ordner, keine Unterordner.
        return @(Get-ChildItem -LiteralPath $item.FullName -File -Filter '*.pdf')
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

function Invoke-ExternalTool {
    # Startet ein externes Konsolenprogramm mit umgeleiteten Streams und liefert
    # Exitcode, Stdout und Stderr. Asynchrones Lesen verhindert, dass große Ausgaben
    # die Pipe blockieren, und PowerShells NativeCommand-Verhalten wirft keine
    # terminierenden Fehler für Nicht-Null-Exitcodes.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ExePath,
        [Parameter(Mandatory)][string] $Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $ExePath
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Programm konnte nicht gestartet werden.' }
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

function Optimize-WithGhostscript {
    # Komprimiert eine PDF-Datei mit Ghostscript (`-dPDFSETTINGS=/ebook`):
    # Bilder werden auf 150 DPI heruntergerechnet und als JPEG eingebettet.
    # Ersetzt die Eingabedatei nur, wenn das Ergebnis kleiner ist; anderenfalls
    # bleibt die Eingabe unverändert. Rückgabe: $true bei Verkleinerung.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $GhostscriptPath,
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf
    )

    $tempPath = Join-Path $Pdf.DirectoryName ('.{0}.{1}.gs.tmp.pdf' -f $Pdf.BaseName, [guid]::NewGuid().ToString('N'))
    try {
        $inputSize = (Get-Item -LiteralPath $Pdf.FullName).Length
        # -dPDFSETTINGS=/ebook: 150 DPI, JPEG (DCT) Kompression - guter Kompromiss
        # aus Größe und Qualität für gescannte Dokumente.
        $gsArgs = '-dBATCH -dNOPAUSE -dQUIET -dSAFER -sDEVICE=pdfwrite -dPDFSETTINGS=/ebook ' +
            '-dCompatibilityLevel=1.5 ' +
            '-sOutputFile="{0}" "{1}"' -f $tempPath, $Pdf.FullName
        $result = Invoke-ExternalTool -ExePath $GhostscriptPath -Arguments $gsArgs
        if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $tempPath)) {
            Write-Host '  Ghostscript: fehlgeschlagen, Stufe übersprungen.' -ForegroundColor DarkYellow
            return $false
        }
        $resultSize = (Get-Item -LiteralPath $tempPath).Length
        if ($resultSize -lt $inputSize) {
            Move-Item -LiteralPath $tempPath -Destination $Pdf.FullName -Force
            Write-Host ('  Ghostscript: {0:N1} MB -> {1:N1} MB' -f ($inputSize / 1MB), ($resultSize / 1MB)) -ForegroundColor DarkGray
            return $true
        }
        Write-Host '  Ghostscript: keine Verkleinerung, Ergebnis verworfen.' -ForegroundColor DarkYellow
        return $false
    }
    catch {
        Write-Host "  Ghostscript: Fehler: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-Ocrmypdf {
    # Führt OCRmyPDF aus und liefert Exitcode, gefilterte Stdout- und ungefilterte
    # Stderr-Zeilen. Die rohe OCRmyPDF-Ausgabe (Fortschrittsbalken mit internen
    # Modulnamen wie _pipeline.py) wird verworfen; nur Warnungen und Fehler aus
    # Stderr sowie relevante Statuszeilen bleiben erhalten.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string[]] $OcrArgs,
        [Parameter(Mandatory)][string] $InputFile,
        [Parameter(Mandatory)][string] $OutputFile
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $PythonPath
    # Argumente als Liste übergeben, damit Pfade mit Leerzeichen korrekt zitiert werden.
    $startInfo.ArgumentList.Add('-m')
    $startInfo.ArgumentList.Add('ocrmypdf')
    foreach ($arg in $OcrArgs) { $startInfo.ArgumentList.Add($arg) }
    $startInfo.ArgumentList.Add('--')
    $startInfo.ArgumentList.Add($InputFile)
    $startInfo.ArgumentList.Add($OutputFile)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'OCRmyPDF konnte nicht gestartet werden.' }
        # Asynchron lesen, damit große Ausgaben die Pipe nicht blockieren.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdOut = $stdoutTask.GetAwaiter().GetResult()
        $stdErr = $stderrTask.GetAwaiter().GetResult()

        # Fortschrittsbalken und interne Modulzeilen (z. B. "_pipeline.py:219")
        # verwerfen; reine Statusmeldungen ohne Modulreferenz behalten.
        $filteredOut = @($stdOut -split '\r?\n' | ForEach-Object {
            $line = $_.Trim()
            if ($line -and $line -notmatch '^[A-Za-z_]+\.py:\d+') { $line }
        })
        [pscustomobject]@{
            ExitCode    = $process.ExitCode
            StdOutLines = $filteredOut
            StdErr      = $stdErr
        }
    }
    finally { $process.Dispose() }
}

function Invoke-PdfProcessing {
    # Verarbeitet eine einzelne PDF-Datei in zwei Stufen:
    #   1. OCRmyPDF: OCR-Textebene ergänzen, optimieren und schiefe Seiten begradigen.
    #      Die Scan-Bilder werden als JPEG mit der übergebenen Qualität eingebettet.
    #   2. Ghostscript (optional): Bilder auf 150 DPI nachkomprimieren (stärkste Stufe).
    # Das Original bleibt unverändert; das Ergebnis wird als <Name>_ocr.pdf
    # neben das Original gelegt. Ein Lauf gilt nur als Fehlschlag, wenn OCRmyPDF
    # fehlschlägt oder das Endergebnis hash-gleich zum Original ist (keine Änderung).
    # WICHTIG: `--output-type pdf` wird bewusst nicht an OCRmyPDF übergeben, da
    # `--pdfa-image-compression` nur bei `--output-type auto` oder `pdfa*` greift.
    # `--optimize 1` statt 3: Stufe 3 erzeugt eine jbig2-Warnung, die wir nicht
    # benötigen (jbig2 wird bewusst nicht installiert).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string] $Language,
        [Parameter(Mandatory)][int] $Quality,
        [Parameter(Mandatory)][int] $Dpi,
        [Parameter(Mandatory)][bool] $Deskew,
        [Parameter(Mandatory)][bool] $RotatePages,
        [Parameter(Mandatory)][bool] $UseGhostscript,
        [string] $GhostscriptPath
    )

    # Temporäre Datei neben der Eingabe, damit Verschieben auf demselben Laufwerk bleibt.
    $tempPath = Join-Path $Pdf.DirectoryName ('.{0}.{1}.tmp.pdf' -f $Pdf.BaseName, [guid]::NewGuid().ToString('N'))
    # Das verarbeitete Ergebnis landet als <Name>_ocr.pdf neben dem Original.
    $outputPath = Join-Path $Pdf.DirectoryName ($Pdf.BaseName + '_ocr' + $Pdf.Extension)
    try {
        Write-Host "Bearbeite: $($Pdf.Name)"
        # Kein --output-type pdf: sonst ignoriert OCRmyPDF --pdfa-image-compression.
        # --optimize 1 statt 3: vermeidet die jbig2-Warnung (jbig2 wird nicht installiert).
        $ocrArgs = @(
            '--skip-text',
            '--optimize', '1',
            '--pdfa-image-compression', 'jpeg',
            '--jpeg-quality', $Quality,
            '--image-dpi', $Dpi,
            '--language', $Language
        )
        if ($Deskew) { $ocrArgs += '--deskew' }
        if ($RotatePages) { $ocrArgs += '--rotate-pages' }

        $ocrResult = Invoke-Ocrmypdf -PythonPath $PythonPath -OcrArgs $ocrArgs -InputFile $Pdf.FullName -OutputFile $tempPath

        # Relevante OCRmyPDF-Meldungen ausgeben (Warnungen auf Stderr, Statuszeilen).
        foreach ($line in $ocrResult.StdErr -split '\r?\n') {
            $trimmed = $line.Trim()
            if ($trimmed -and $trimmed -notmatch '^\s*$') {
                Write-Host "  [OCRmyPDF] $trimmed" -ForegroundColor DarkYellow
            }
        }
        foreach ($line in $ocrResult.StdOutLines) {
            Write-Host "  [OCRmyPDF] $line" -ForegroundColor DarkGray
        }

        if ($ocrResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $tempPath)) {
            throw "OCRmyPDF fehlgeschlagen (Exitcode $($ocrResult.ExitCode))."
        }

        # Nachgelagerte Ghostscript-Optimierung (nur bei Verkleinerung übernommen).
        if ($UseGhostscript -and $GhostscriptPath) {
            $gsResult = Get-Item -LiteralPath $tempPath
            Optimize-WithGhostscript -GhostscriptPath $GhostscriptPath -Pdf $gsResult | Out-Null
        }

        $originalSize = (Get-Item -LiteralPath $Pdf.FullName).Length
        $resultSize = (Get-Item -LiteralPath $tempPath).Length

        # Hash-Vergleich: Ein hash-gleiches Ergebnis bedeutet, dass keine
        # inhaltliche Veränderung stattgefunden hat - dann ist der Lauf ein
        # Fehlschlag. Ein größeres, aber verändertes Ergebnis ist ein Erfolg.
        $originalHash = Get-FileSha256 -Path $Pdf.FullName
        $resultHash = Get-FileSha256 -Path $tempPath
        if ($originalHash -eq $resultHash) {
            Write-Host '  Ergebnis ist identisch zum Original (keine Änderung); Datei wird verworfen.' -ForegroundColor Yellow
            return $false
        }

        # Bestehendes _ocr-Ergebnis aus einem früheren Lauf ersetzen.
        if (Test-Path -LiteralPath $outputPath) {
            Remove-Item -LiteralPath $outputPath -Force
        }
        Move-Item -LiteralPath $tempPath -Destination $outputPath -Force
        if ($resultSize -lt $originalSize) {
            Write-Host ('  Optimiert: {0:N1} MB -> {1:N1} MB' -f ($originalSize / 1MB), ($resultSize / 1MB)) -ForegroundColor Green
        }
        else {
            Write-Host ('  Verarbeitet (größer als Original): {0:N1} MB -> {1:N1} MB' -f ($originalSize / 1MB), ($resultSize / 1MB)) -ForegroundColor Cyan
        }
        Write-Host "  Gespeichert: $outputPath"
        return $true
    }
    catch {
        Write-Warning "Fehler bei '$($Pdf.Name)': $($_.Exception.Message)"
        return $false
    }
    finally {
        # Temporäre Datei auch im Fehlerfall zuverlässig entfernen.
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- Abhängigkeiten prüfen ---------------------------------------------------
# Programme und Python-Module vorab gesammelt prüfen, damit der Benutzer
# alle Installationshinweise auf einmal erhält.
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

# Pflichtsprachen prüfen: Fehlt deu oder eng, Download-Hinweis und Programmende.
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
Write-Host "OCR-Sprachen: $languageSelection" -ForegroundColor Cyan

# --- PDFs verarbeiten -----------------------------------------------------------
$successCount = 0
$failureCount = 0
foreach ($pdf in $pdfFiles) {
    if (Invoke-PdfProcessing -Pdf $pdf -PythonPath $dependencyCheck.PythonPath -Language $languageSelection -Quality $JpegQuality -Dpi $ImageDpi -Deskew:$Deskew -RotatePages:$RotatePages -UseGhostscript:$UseGhostscript -GhostscriptPath $dependencyCheck.GhostscriptPath) { $successCount++ }
    else { $failureCount++ }
}
Write-Host ''
Write-Host "Abgeschlossen: $successCount erfolgreich, $failureCount fehlgeschlagen." -ForegroundColor Cyan
Write-Host 'Verarbeitete Dateien liegen mit dem Suffix _ocr neben den Originalen; die Originale bleiben unverändert.'
