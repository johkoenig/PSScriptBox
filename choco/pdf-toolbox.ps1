<#
.SYNOPSIS
    Optimiert PDFs und ergänzt bei Bedarf eine OCR-Textebene.

.DESCRIPTION
    Verarbeitet eine einzelne PDF-Datei oder alle PDF-Dateien direkt in
    einem angegebenen Ordner (keine Unterordner). Erstellt vor der
    Verarbeitung eine Sicherung mit dem Suffix _orig. Das Original wird
    nur durch ein erfolgreich verarbeitetes, kleineres Ergebnis ersetzt.

    Das Skript selbst benötigt keine Administratorrechte und installiert
    keine Software. Fehlende Abhängigkeiten müssen separat installiert werden.

.NOTES
    Abhängigkeiten:
      - Python
      - OCRmyPDF (Python-Modul)
      - Tesseract
      - Ghostscript

    Beispielinstallation aus einer PowerShell mit Administratorrechten:
      choco install python tesseract ghostscript -y
      py -m pip install --user ocrmypdf

    Sprachdaten (traineddata) sind separat für Tesseract zu installieren.
    Siehe https://github.com/tesseract-ocr/tessdata_fast bzw.
    https://github.com/tesseract-ocr/tessdata_best. Die benötigten Dateien
    gehören in den tessdata-Ordner von Tesseract. Danach `tesseract --list-langs`
    ausführen und eine neue PowerShell-Sitzung öffnen.

    Anschließend das Skript in einer normalen PowerShell starten.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    $startInfo.Arguments = "-c `"import $ModuleName`""
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
    $pythonPath = Get-ExecutablePath -Name 'py'
    if (-not $pythonPath) { $pythonPath = Get-ExecutablePath -Name 'python' }
    if (-not $pythonPath) { $missing.Add('Python (py.exe oder python.exe)') }
    if (-not (Get-ExecutablePath -Name 'tesseract')) { $missing.Add('Tesseract') }
    if (
        -not (Get-ExecutablePath -Name 'gswin64c') -and
        -not (Get-ExecutablePath -Name 'gswin32c') -and
        -not (Get-ExecutablePath -Name 'gs')
    ) { $missing.Add('Ghostscript') }

    # pngquant und jbig2enc sind für OCRmyPDF-Optimierung optional.
    # Fehlende optionale Werkzeuge dürfen den Lauf nicht blockieren.
    if ($pythonPath -and -not (Test-PythonModule -PythonPath $pythonPath -ModuleName 'ocrmypdf')) {
        $missing.Add('OCRmyPDF (Python-Modul)')
    }

    [pscustomobject]@{ PythonPath = $pythonPath; Missing = $missing }
}

function Get-TesseractLanguages {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $TesseractPath)

    # Native Prozessausgabe gezielt abfangen, damit Fehlerausgaben nicht
    # durch PowerShells NativeCommand-Verhalten als Terminierungsfehler enden.
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $TesseractPath
    $startInfo.Arguments = '--list-langs'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Tesseract konnte nicht gestartet werden.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "Tesseract --list-langs fehlgeschlagen: $stderr"
        }
        return @($stdout -split '\r?\n' | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -ne 'List of available languages in "tessdata" (2):' -and $_ -notmatch '^List of available languages' })
    }
    finally { $process.Dispose() }
}

function Get-PdfInputFile {
    [CmdletBinding()]
    param()

    $inputPath = Read-Host 'Pfad zu einer PDF-Datei oder einem Ordner mit PDFs'
    if ([string]::IsNullOrWhiteSpace($inputPath)) { throw 'Es wurde kein Pfad eingegeben.' }
    $inputPath = [Environment]::ExpandEnvironmentVariables($inputPath.Trim().Trim('"'))
    if (-not (Test-Path -LiteralPath $inputPath)) { throw "Pfad nicht gefunden: $inputPath" }
    $item = Get-Item -LiteralPath $inputPath
    if ($item.PSIsContainer) {
        return @(Get-ChildItem -LiteralPath $item.FullName -File -Filter '*.pdf')
    }
    if ($item.Extension -ine '.pdf') { throw 'Die ausgewählte Datei hat keine .pdf-Endung.' }
    return @($item)
}

function Invoke-PdfProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string] $Language
    )

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
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Prüfe vor der Verarbeitung alle erforderlichen Programme und Module.
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

$tesseractPath = Get-ExecutablePath -Name 'tesseract'
try {
    $installedLanguages = @(Get-TesseractLanguages -TesseractPath $tesseractPath)
}
catch {
    Write-Error "Tesseract-Sprachen konnten nicht ermittelt werden. Prüfe `"tesseract --list-langs`": $($_.Exception.Message)"
    exit 1
}
if ($installedLanguages.Count -eq 0) {
    Write-Error 'Tesseract meldet keine installierten Sprachdaten. Die Sprachdateien müssen separat beschafft und im tessdata-Ordner abgelegt werden; eine erneute Chocolatey-Installation von Tesseract hilft nicht.'
    exit 1
}

try { $pdfFiles = @(Get-PdfInputFile) }
catch { Write-Error $_.Exception.Message; exit 1 }
if ($pdfFiles.Count -eq 0) { Write-Host 'Keine PDFs gefunden.'; exit 0 }

Write-Host "`nInstallierte Tesseract-Sprachen: $($installedLanguages -join ', ')" -ForegroundColor Cyan
Write-Host 'Sprachdaten können beispielsweise aus tessdata_fast oder tessdata_best bezogen und in den Tesseract-tessdata-Ordner kopiert werden.'
$defaultLanguage = if ($installedLanguages -contains 'deu') { 'deu' } else { $installedLanguages[0] }
$language = Read-Host "OCR-Sprachen mit + kombinieren (z. B. deu+eng). Verfügbar: $($installedLanguages -join ', ') [$defaultLanguage]"
if ([string]::IsNullOrWhiteSpace($language)) { $language = $defaultLanguage }
$requestedLanguages = @($language -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$missingLanguages = @($requestedLanguages | Where-Object { $installedLanguages -notcontains $_ })
if ($missingLanguages.Count -gt 0) {
    Write-Error ("Fehlende Tesseract-Sprachdaten: {0}. Installierte Sprachen: {1}. Beschaffe die passenden .traineddata-Dateien separat, lege sie im tessdata-Ordner ab und bestätige dies mit `tesseract --list-langs`. Keine Chocolatey-Neuinstallation erforderlich." -f ($missingLanguages -join ', '), ($installedLanguages -join ', '))
    exit 1
}

$successCount = 0
$failureCount = 0
foreach ($pdf in $pdfFiles) {
    if (Invoke-PdfProcessing -Pdf $pdf -PythonPath $dependencyCheck.PythonPath -Language $language) { $successCount++ }
    else { $failureCount++ }
}
Write-Host "`nAbgeschlossen: $successCount erfolgreich, $failureCount fehlgeschlagen."
Write-Host 'Sicherungskopien mit dem Suffix _orig liegen neben den Originalen.'
