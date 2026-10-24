<#
.SYNOPSIS
    Optimiert PDFs, begradigt schiefe Scan-Seiten und ergänzt eine OCR-Textebene.

.DESCRIPTION
    Verarbeitet eine einzelne PDF-Datei oder alle PDF-Dateien direkt in einem angegebenen
    Ordner (keine Unterordner). Das Original bleibt stets unverändert erhalten; das
    verarbeitete Ergebnis wird als neue Datei mit dem Suffix _ocr neben das Original gelegt.

    BEIGRADIGUNG:
      - Schiefe Scan-Seiten werden automatisch begradigt (`--deskew`, standardmäßig aktiv).
      - Verdrehte Seiten (90°, 180°, 270°) werden NICHT automatisch korrigiert
        (`--rotate-pages` ist standardmäßig deaktiviert und kann über den Parameter
        `-RotatePages` explizit aktiviert werden).

    KOMPRESSION:
      Die Scan-Bilder werden mit 300 DPI neu abgetastet und als JPEG mit Qualität 75
      eingebettet (`--pdfa-image-compression jpeg --jpeg-quality 75 --image-dpi 300`).
      Die Auflösungsbegrenzung auf 300 DPI reduziert die Dateigröße deutlich, ohne die
      Lesbarkeit nennenswert zu beeinträchtigen. Bei reinen Textdokumenten ohne Bilder
      bleibt diese Einstellung wirkungslos.

    ERGEBNISPRÜFUNG:
      Ein Lauf gilt nur dann als fehlgeschlagen, wenn OCRmyPDF tatsächlich fehlschlägt oder
      das Ergebnis byte-identisch (hash-gleich) zum Original ist, d. h. keine Veränderung
      stattgefunden hat. Ein größeres, aber inhaltlich verändertes Ergebnis wird als
      Erfolg gewertet und als _ocr-Datei abgelegt.

    Das Skript selbst benötigt keine Administratorrechte und installiert keine Software.
    Fehlende Programme meldet es mit Installationshinweisen. Fehlende Tesseract-Sprachdaten
    werden mit einem Zweizeiler gemeldet, der den Benutzer auffordert, einen Download-Befehl
    in einer Admin-Shell auszuführen, um alle Sprachen herunterzuladen.

.PARAMETER Language
    OCR-Sprachen als mit '+' kombinierte Tesseract-Codes, z. B. 'deu+eng'.
    Ohne Angabe wird interaktiv nachgefragt; Vorgabe ist die Standardfolge
    'deu+eng+fra+ita+spa' (Deutsch, Englisch, Französisch, Italienisch, Spanisch, in dieser
    Reihenfolge).

.PARAMETER InputPath
    Optionaler Pfad zu einer PDF-Datei oder einem Ordner mit PDF-Dateien.
    Ohne Angabe wird interaktiv danach gefragt.

.PARAMETER JpegQuality
    JPEG-Qualität für die eingebetteten Scan-Bilder (1-100).
    Vorgabe ist 75: guter Kompromiss aus Dateigröße und Lesbarkeit.

.PARAMETER ImageDpi
    Maximale Auflösung der eingebetteten Scan-Bilder in DPI.
    Vorgabe ist 300: typische Scan-Auflösung für gut lesbare Dokumente bei deutlich
    reduzierter Dateigröße. Höhere Werte (z. B. 400-600) nur bei sehr kleinen Schriften
    oder Grafiken nötig.

.PARAMETER Deskew
    Legt fest, ob schiefe Scan-Seiten begradigt werden sollen (Standard: $true).
    Bei aktivierter Begradigung wird `--deskew` an OCRmyPDF übergeben.

.PARAMETER RotatePages
    Legt fest, ob verdrehte Seiten (90°, 180°, 270°) automatisch korrigiert werden sollen
    (Standard: $false). Bei Aktivierung wird `--rotate-pages` an OCRmyPDF übergeben.

.EXAMPLE
    .\pdf-toolbox.ps1
    Interaktiver Start mit der Standard-Sprachfolge deu+eng+fra+ita+spa, JPEG-Qualität 75,
    300 DPI, automatischer Begradigung schiefer Seiten und deaktivierter automatischer
    Drehkorrektur. Ergebnisse werden als <Name>_ocr.pdf abgelegt.

.EXAMPLE
    .\pdf-toolbox.ps1 -InputPath 'C:\PDFs' -Language 'deu+eng' -JpegQuality 65 -ImageDpi 200 -Deskew:$true -RotatePages:$true
    Verarbeitet alle PDFs in C:\PDFs mit deutscher und englischer OCR, stärkerer JPEG-
    Kompression, 200 DPI, automatischer Begradigung und automatischer Drehkorrektur.

.NOTES
    Abhängigkeiten:
      - Python
      - OCRmyPDF (Python-Modul)
      - Tesseract
      - Ghostscript

    Beispielinstallation aus einer PowerShell mit Administratorrechten:
      choco install python tesseract ghostscript -y
      py -m pip install --user ocrmypdf

    Tesseract-Sprachdaten (.traineddata) werden nicht mitinstalliert.
    Quelle für alle Sprachen: https://github.com/tesseract-ocr/tessdata
    Fehlende Sprachen lädt der vom Skript ausgegebene Befehl in einer
    Admin-Shell herunter. Danach `tesseract --list-langs` prüfen und eine
    neue PowerShell-Sitzung öffnen.

    WEITERE MÖGLICHKEITEN ZUR REDUZIERUNG DER DATEIGRÖSSE:
      - Niedrigere JPEG-Qualität: -JpegQuality 60 (noch gut lesbar, deutlich kleiner).
      - Niedrigere Auflösung: -ImageDpi 200 (für Dokumente ohne kleine Schriften ausreichend).
      - Graustufen statt Farbe: OCRmyPDF-Option `--grayscale` (spart zusätzlich, wenn die
        Dokumente keine Farbe benötigen).
      - Reines Schwarz-Weiß: OCRmyPDF-Option `--threshold` (stärkste Kompression, aber
        Verlust von Graustufen und Hintergrunddetails).
      - Externe Werkzeuge: `qpdf --optimize-images` oder Ghostscript direkt
        (`gs -sDEVICE=pdfwrite -dPDFSETTINGS=/ebook`) als nachgelagerter Schritt.
#>

[CmdletBinding()]
param(
    # Abweichende Sprachfolge, z. B. 'deu+eng'. Leer = interaktive Abfrage.
    [string] $Language,

    # Optionaler Pfad zu einer PDF-Datei oder einem Ordner mit PDF-Dateien.
    [string] $InputPath,

    # JPEG-Qualität für eingebettete Scan-Bilder (1-100). Vorgabe 75.
    [ValidateRange(1, 100)]
    [int] $JpegQuality = 75,

    # Maximale Auflösung der eingebetteten Scan-Bilder in DPI. Vorgabe 300.
    [ValidateRange(50, 1200)]
    [int] $ImageDpi = 300,

    # Begradigung schiefer Scan-Seiten aktivieren (Standard true).
    [bool] $Deskew = $true,

    # Automatische Drehkorrektur für 90°/180°/270°-Verdrehungen (Standard false).
    [bool] $RotatePages = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Standard-Sprachfolge für die OCR: Deutsch, Englisch, Französisch,
# Italienisch, Spanisch - in dieser Reihenfolge.
$script:DefaultLanguage = 'deu+eng+fra+ita+spa'

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
    [CmdletBinding()]
    param()

    $missing = [System.Collections.Generic.List[string]]::new()
    $pythonPath = Get-ExecutablePath -Name 'py'
    if (-not $pythonPath) { $pythonPath = Get-ExecutablePath -Name 'python' }
    if (-not $pythonPath) { $missing.Add('Python (py.exe oder python.exe)') }
    if (-not (Get-ExecutablePath -Name 'tesseract')) { $missing.Add('Tesseract') }
    if (
        -not (Get-ExecutablePath -Name 'gswin64c') -and
        -not (Get-ExecutablePath -Name 'gswin32c') -and
        -not (Get-ExecutablePath -Name 'gs')
    ) { $missing.Add('Ghostscript') }

    # pngquant ist für die OCRmyPDF-Optimierung optional; ein Fehlen darf den
    # Lauf nicht blockieren. jbig2 wird bewusst nicht verwendet (nur für
    # Schwarz-Weiß-Bilder relevant, hier JPEG-Kompression im Einsatz).
    if ($pythonPath -and -not (Test-PythonModule -PythonPath $pythonPath -ModuleName 'ocrmypdf')) {
        $missing.Add('OCRmyPDF (Python-Modul)')
    }

    [pscustomobject]@{ PythonPath = $pythonPath; Missing = $missing }
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
    # Zweizeiler bei fehlenden Sprachdaten: Zeile 1 fordert den Benutzer
    # auf, den Download in einer Admin-Shell auszuführen, Zeile 2 ist der
    # Befehl, der alle Sprachen aus dem tessdata-Repository herunterlädt
    # und im tessdata-Ordner ablegt.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $MissingLanguages,
        [Parameter(Mandatory)][string[]] $InstalledLanguages,
        [Parameter(Mandatory)][string] $TessdataPath
    )

    $downloadCommand = "Invoke-WebRequest '$script:TessdataZipUrl' -OutFile `$env:TEMP\tessdata.zip; " +
        "Expand-Archive `$env:TEMP\tessdata.zip `$env:TEMP\tessdata -Force; " +
        "Copy-Item `$env:TEMP\tessdata\tessdata-main\*.traineddata '$TessdataPath\' -Force"

    Write-Host ''
    Write-Host "Fehlende Tesseract-Sprachdaten: $($MissingLanguages -join ', ') (installiert: $($InstalledLanguages -join ', ')). Bitte öffne eine PowerShell als Administrator und führe folgenden Befehl aus, um alle Sprachen herunterzuladen:"
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

function Invoke-PdfProcessing {
    # Verarbeitet eine einzelne PDF-Datei mit OCRmyPDF: OCR-Textebene ergänzen,
    # optimieren und schiefe Seiten begradigen. Die Scan-Bilder werden mit der
    # übergebenen Auflösung (DPI) neu abgetastet und als JPEG mit der übergebenen
    # Qualität eingebettet, was die Dateigröße deutlich reduziert.
    # Das Original bleibt unverändert; das Ergebnis wird als <Name>_ocr.pdf
    # neben das Original gelegt. Ein Lauf gilt nur als Fehlschlag, wenn OCRmyPDF
    # fehlschlägt oder das Ergebnis hash-gleich zum Original ist (keine Änderung).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string] $Language,
        [Parameter(Mandatory)][int] $Quality,
        [Parameter(Mandatory)][int] $Dpi,
        [Parameter(Mandatory)][bool] $Deskew,
        [Parameter(Mandatory)][bool] $RotatePages
    )

    # Temporäre Datei neben der Eingabe, damit Verschieben auf demselben Laufwerk bleibt.
    $tempPath = Join-Path $Pdf.DirectoryName ('.{0}.{1}.tmp.pdf' -f $Pdf.BaseName, [guid]::NewGuid().ToString('N'))
    # Das verarbeitete Ergebnis landet als <Name>_ocr.pdf neben dem Original.
    $outputPath = Join-Path $Pdf.DirectoryName ($Pdf.BaseName + '_ocr' + $Pdf.Extension)
    try {
        Write-Host "Bearbeite: $($Pdf.Name)"
        $ocrArgs = @(
            '--skip-text',
            '--optimize', '3',
            '--output-type', 'pdf',
            '--pdfa-image-compression', 'jpeg',
            '--jpeg-quality', $Quality,
            '--image-dpi', $Dpi,
            '--language', $Language
        )
        if ($Deskew) { $ocrArgs += '--deskew' }
        if ($RotatePages) { $ocrArgs += '--rotate-pages' }

        & $PythonPath -m ocrmypdf $ocrArgs -- $Pdf.FullName $tempPath
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempPath)) {
            throw "OCRmyPDF fehlgeschlagen (Exitcode $LASTEXITCODE)."
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
            return $false
        }

        # Bestehendes _ocr-Ergebnis aus einem früheren Lauf ersetzen.
        if (Test-Path -LiteralPath $outputPath) {
            Remove-Item -LiteralPath $outputPath -Force
        }
        Move-Item -LiteralPath $tempPath -Destination $outputPath -Force
        if ($resultSize -lt $originalSize) {
            Write-Host ('Optimiert: {0:N1} MB -> {1:N1} MB ({2})' -f ($originalSize / 1MB), ($resultSize / 1MB), $outputPath) -ForegroundColor Green
        }
        else {
            Write-Host ('Verarbeitet (größer als Original): {0:N1} MB -> {1:N1} MB ({2})' -f ($originalSize / 1MB), ($resultSize / 1MB), $outputPath) -ForegroundColor Cyan
        }
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
    Write-Host '  choco install python tesseract ghostscript -y'
    Write-Host '  py -m pip install --user ocrmypdf'
    Write-Host "`nDanach starte dieses Skript erneut in einer normalen PowerShell."
    exit 1
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
# Spanisch. Über -Language oder die interaktive Abfrage kann eine abweichende
# Sprachfolge vorgegeben werden; die Reihenfolge bestimmt die Priorität.
Write-Host "`nInstallierte Tesseract-Sprachen: $($installedLanguages -join ', ')" -ForegroundColor Cyan
if (-not [string]::IsNullOrWhiteSpace($Language)) {
    $languageSelection = $Language.Trim()
}
else {
    $languageSelection = Read-Host "OCR-Sprachen mit + kombinieren (z. B. deu+eng). Verfügbar: $($installedLanguages -join ', ') [$script:DefaultLanguage]"
    if ([string]::IsNullOrWhiteSpace($languageSelection)) { $languageSelection = $script:DefaultLanguage }
}

# Reihenfolge der Eingabe bleibt erhalten und wird so an OCRmyPDF übergeben.
$requestedLanguages = @($languageSelection -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$missingLanguages = @($requestedLanguages | Where-Object { $installedLanguages -notcontains $_ })
if ($missingLanguages.Count -gt 0) {
    Show-LanguageDownloadHint -MissingLanguages $missingLanguages -InstalledLanguages $installedLanguages -TessdataPath $tesseractInfo.TessdataPath
    exit 1
}

# --- PDFs verarbeiten -----------------------------------------------------------
$successCount = 0
$failureCount = 0
foreach ($pdf in $pdfFiles) {
    if (Invoke-PdfProcessing -Pdf $pdf -PythonPath $dependencyCheck.PythonPath -Language $languageSelection -Quality $JpegQuality -Dpi $ImageDpi -Deskew:$Deskew -RotatePages:$RotatePages) { $successCount++ }
    else { $failureCount++ }
}
Write-Host "`nAbgeschlossen: $successCount erfolgreich, $failureCount fehlgeschlagen."
Write-Host 'Verarbeitete Dateien liegen mit dem Suffix _ocr neben den Originalen; die Originale bleiben unverändert.'
