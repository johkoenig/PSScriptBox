<#
.SYNOPSIS
    Optimiert PDFs und ergänzt bei Bedarf eine OCR-Textebene.

.DESCRIPTION
    Verarbeitet eine einzelne PDF-Datei oder alle PDF-Dateien direkt in
    einem angegebenen Ordner (keine Unterordner). Vor der Verarbeitung
    wird eine Sicherung mit dem Suffix _orig angelegt. Das Original wird
    nur durch ein erfolgreich verarbeitetes, kleineres Ergebnis ersetzt.

    Das Skript selbst benötigt keine Administratorrechte und installiert
    keine Software. Fehlende Programme meldet es mit Installationshinweisen.
    Fehlende Tesseract-Sprachdaten meldet es mit einem Zweizeiler, der den
    Benutzer auffordert, einen Download-Befehl in einer Admin-Shell
    auszuführen, um alle Sprachen herunterzuladen.

.PARAMETER Language
    OCR-Sprachen als mit '+' kombinierte Tesseract-Codes, z. B. 'deu+eng'.
    Ohne Angabe wird interaktiv nachgefragt; Vorgabe ist die Standardfolge
    'deu+eng+fra+ita+spa' (Deutsch, Englisch, Französisch, Italienisch,
    Spanisch, in dieser Reihenfolge).

.PARAMETER InputPath
    Optionaler Pfad zu einer PDF-Datei oder einem Ordner mit PDF-Dateien.
    Ohne Angabe wird interaktiv danach gefragt.

.EXAMPLE
    .\pdf-toolbox.ps1
    Interaktiver Start mit der Standard-Sprachfolge deu+eng+fra+ita+spa.

.EXAMPLE
    .\pdf-toolbox.ps1 -InputPath 'C:\PDFs' -Language 'deu+eng'
    Verarbeitet alle PDFs in C:\PDFs mit deutscher und englischer OCR.

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
#>

[CmdletBinding()]
param(
    # Abweichende Sprachfolge, z. B. 'deu+eng'. Leer = interaktive Abfrage.
    [string] $Language,

    # Optionaler Pfad zu einer PDF-Datei oder einem Ordner mit PDF-Dateien.
    [string] $InputPath
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

    # pngquant und jbig2enc sind für die OCRmyPDF-Optimierung optional;
    # fehlende optionale Werkzeuge dürfen den Lauf nicht blockieren.
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

function Invoke-PdfProcessing {
    # Verarbeitet eine einzelne PDF-Datei mit OCRmyPDF: OCR-Textebene
    # ergänzen und optimieren. Das Original wird nur ersetzt, wenn das
    # Ergebnis kleiner ist; vorher wird eine Sicherung mit _orig angelegt.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string] $Language
    )

    # Temporäre Datei neben der Eingabe, damit Verschieben auf demselben Laufwerk bleibt.
    $tempPath = Join-Path $Pdf.DirectoryName ('.{0}.{1}.tmp.pdf' -f $Pdf.BaseName, [guid]::NewGuid().ToString('N'))
    $backupPath = Join-Path $Pdf.DirectoryName ($Pdf.BaseName + '_orig' + $Pdf.Extension)
    try {
        Write-Host "Bearbeite: $($Pdf.Name)"
        & $PythonPath -m ocrmypdf --skip-text --optimize 3 --output-type pdf --language $Language -- $Pdf.FullName $tempPath
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempPath)) {
            throw "OCRmyPDF fehlgeschlagen (Exitcode $LASTEXITCODE)."
        }
        $originalSize = (Get-Item -LiteralPath $Pdf.FullName).Length
        $resultSize = (Get-Item -LiteralPath $tempPath).Length
        if ($resultSize -ge $originalSize) {
            Write-Host 'Ergebnis ist nicht kleiner; Original bleibt unverändert und es wird keine Sicherung angelegt.' -ForegroundColor Yellow
            return $false
        }
        # Sicherung nur einmalig anlegen; eine vorhandene _orig-Datei bleibt unverändert.
        if (-not (Test-Path -LiteralPath $backupPath)) {
            Copy-Item -LiteralPath $Pdf.FullName -Destination $backupPath
        }
        else {
            Write-Host "Vorhandene Sicherung bleibt unverändert: $backupPath" -ForegroundColor DarkYellow
        }
        Move-Item -LiteralPath $tempPath -Destination $Pdf.FullName -Force
        Write-Host ('Optimiert: {0:N1} MB -> {1:N1} MB' -f ($originalSize / 1MB), ($resultSize / 1MB)) -ForegroundColor Green
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
    if (Invoke-PdfProcessing -Pdf $pdf -PythonPath $dependencyCheck.PythonPath -Language $languageSelection) { $successCount++ }
    else { $failureCount++ }
}
Write-Host "`nAbgeschlossen: $successCount erfolgreich, $failureCount fehlgeschlagen."
Write-Host 'Sicherungskopien mit dem Suffix _orig liegen neben den Originalen.'
