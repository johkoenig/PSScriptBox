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

    Anschließend das Skript in einer normalen PowerShell starten.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ExecutablePath {
    <#
    .SYNOPSIS
        Liefert den Pfad zu einem ausführbaren Kommando.

    .DESCRIPTION
        Sucht ein Kommando über Get-Command. Gibt bei fehlendem Kommando
        $null zurück, anstatt einen Fehler auszulösen.

    .PARAMETER Name
        Name des Kommandos, zum Beispiel py oder tesseract.

    .OUTPUTS
        System.String oder $null
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -eq $command) {
        return $null
    }

    return $command.Source
}

function Test-PythonModule {
    <#
    .SYNOPSIS
        Prüft ein Python-Modul ohne den erwarteten Importfehler auszugeben.

    .DESCRIPTION
        Startet Python als separaten Prozess und prüft dessen Exitcode.
        Standardausgabe und Fehlerausgabe werden umgeleitet und nicht in
        der PowerShell-Konsole angezeigt. So entsteht beim fehlenden Modul
        kein NativeCommandError.

    .PARAMETER PythonPath
        Pfad zu py.exe oder python.exe.

    .PARAMETER ModuleName
        Name des Python-Moduls, das importiert werden soll.

    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $PythonPath,

        [Parameter(Mandatory)]
        [string] $ModuleName
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
        if (-not $process.Start()) {
            return $false
        }

        # Drain both streams to avoid blocking if the child process writes
        # more output than the operating-system pipe buffer can hold.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdoutTask.GetAwaiter().GetResult() | Out-Null
        $stderrTask.GetAwaiter().GetResult() | Out-Null

        return ($process.ExitCode -eq 0)
    }
    catch {
        return $false
    }
    finally {
        $process.Dispose()
    }
}

function Get-MissingDependency {
    <#
    .SYNOPSIS
        Prüft, ob die benötigten Programme und das OCRmyPDF-Modul vorhanden sind.

    .DESCRIPTION
        Sucht Python, Tesseract, Ghostscript und pngquant im PATH und testet
        den Import des OCRmyPDF-Moduls. Der Python-Importtest unterdrückt
        erwartete Fehlermeldungen.

    .OUTPUTS
        PSCustomObject mit den Python-Pfad und einer Liste fehlender Abhängigkeiten.
    #>
    [CmdletBinding()]
    param()

    $missing = [System.Collections.Generic.List[string]]::new()

    $pythonPath = Get-ExecutablePath -Name 'py'
    if (-not $pythonPath) {
        $pythonPath = Get-ExecutablePath -Name 'python'
    }
    if (-not $pythonPath) {
        $missing.Add('Python (py.exe oder python.exe)')
    }

    if (-not (Get-ExecutablePath -Name 'tesseract')) {
        $missing.Add('Tesseract')
    }

    if (
        -not (Get-ExecutablePath -Name 'gswin64c') -and
        -not (Get-ExecutablePath -Name 'gswin32c') -and
        -not (Get-ExecutablePath -Name 'gs')
    ) {
        $missing.Add('Ghostscript')
    }

    # OCRmyPDF benötigt pngquant bei den Optimierungsstufen 2 und 3.
    if (-not (Get-ExecutablePath -Name 'pngquant')) {
        $missing.Add('pngquant (für --optimize 2/3)')
    }

    if ($pythonPath -and -not (Test-PythonModule -PythonPath $pythonPath -ModuleName 'ocrmypdf')) {
        $missing.Add('OCRmyPDF (Python-Modul)')
    }

    [pscustomobject]@{
        PythonPath = $pythonPath
        Missing    = $missing
    }
}

function Get-PdfInputFile {
    <#
    .SYNOPSIS
        Fragt nach einer PDF-Datei oder einem Ordner mit PDFs.

    .DESCRIPTION
        Bei Auswahl eines Ordners werden nur PDF-Dateien direkt in diesem
        Ordner berücksichtigt. Unterordner werden nicht durchsucht.

    .OUTPUTS
        System.IO.FileInfo[]
    #>
    [CmdletBinding()]
    param()

    $inputPath = Read-Host 'Pfad zu einer PDF-Datei oder einem Ordner mit PDFs'
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
        throw 'Es wurde kein Pfad eingegeben.'
    }

    $inputPath = [Environment]::ExpandEnvironmentVariables(
        $inputPath.Trim().Trim('"')
    )

    if (-not (Test-Path -LiteralPath $inputPath)) {
        throw "Pfad nicht gefunden: $inputPath"
    }

    $item = Get-Item -LiteralPath $inputPath

    if ($item.PSIsContainer) {
        return @(Get-ChildItem -LiteralPath $item.FullName -File -Filter '*.pdf')
    }

    if ($item.Extension -ine '.pdf') {
        throw 'Die ausgewählte Datei hat keine .pdf-Endung.'
    }

    return @($item)
}

function Invoke-PdfProcessing {
    <#
    .SYNOPSIS
        Verarbeitet eine PDF-Datei und ersetzt sie nur bei erfolgreicher Verkleinerung.

    .DESCRIPTION
        Erstellt zunächst eine temporäre Ausgabedatei. Bei einem Fehler oder
        wenn das Ergebnis nicht kleiner ist, bleibt das Original unverändert
        und es wird keine _orig-Sicherung angelegt. Eine Sicherung wird erst
        unmittelbar vor dem Ersetzen des Originals erstellt.

    .PARAMETER Pdf
        Zu verarbeitende PDF-Datei.

    .PARAMETER PythonPath
        Pfad zum Python-Interpreter beziehungsweise Launcher.

    .PARAMETER Language
        OCR-Sprachcode, zum Beispiel deu oder deu+eng.

    .OUTPUTS
        System.Boolean. True bei erfolgreicher Verarbeitung, sonst False.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo] $Pdf,

        [Parameter(Mandatory)]
        [string] $PythonPath,

        [Parameter(Mandatory)]
        [string] $Language
    )

    $tempPath = Join-Path $Pdf.DirectoryName (
        '.{0}.{1}.tmp.pdf' -f $Pdf.BaseName, [guid]::NewGuid().ToString('N')
    )
    $backupPath = Join-Path $Pdf.DirectoryName ($Pdf.BaseName + '_orig' + $Pdf.Extension)

    try {
        Write-Host "Bearbeite: $($Pdf.Name)"

        & $PythonPath -m ocrmypdf `
            --skip-text `
            --optimize 3 `
            --output-type pdf `
            --language $Language `
            -- $Pdf.FullName $tempPath

        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempPath)) {
            throw "OCRmyPDF fehlgeschlagen (Exitcode $LASTEXITCODE)."
        }

        $originalSize = (Get-Item -LiteralPath $Pdf.FullName).Length
        $resultSize = (Get-Item -LiteralPath $tempPath).Length

        if ($resultSize -ge $originalSize) {
            Write-Host 'Ergebnis ist nicht kleiner; Original bleibt unverändert und es wird keine Sicherung angelegt.' `
                -ForegroundColor Yellow
            return $false
        }

        # Sicherung erst anlegen, wenn ein kleineres Ergebnis vorliegt.
        if (-not (Test-Path -LiteralPath $backupPath)) {
            Copy-Item -LiteralPath $Pdf.FullName -Destination $backupPath
        }
        else {
            Write-Host "Vorhandene Sicherung bleibt unverändert: $backupPath" `
                -ForegroundColor DarkYellow
        }

        Move-Item -LiteralPath $tempPath -Destination $Pdf.FullName -Force

        Write-Host (
            'Optimiert: {0:N1} MB -> {1:N1} MB' -f
            ($originalSize / 1MB), ($resultSize / 1MB)
        ) -ForegroundColor Green

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

# Prüfe vor der Verarbeitung alle erforderlichen Abhängigkeiten.
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

try {
    $pdfFiles = @(Get-PdfInputFile)
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

if ($pdfFiles.Count -eq 0) {
    Write-Host 'Keine PDFs gefunden.'
    exit 0
}

$language = Read-Host 'OCR-Sprachen (z. B. deu oder deu+eng) [deu]'
if ([string]::IsNullOrWhiteSpace($language)) {
    $language = 'deu'
}

$successCount = 0
$failureCount = 0

foreach ($pdf in $pdfFiles) {
    if (Invoke-PdfProcessing -Pdf $pdf -PythonPath $dependencyCheck.PythonPath -Language $language) {
        $successCount++
    }
    else {
        $failureCount++
    }
}

Write-Host "`nAbgeschlossen: $successCount erfolgreich, $failureCount fehlgeschlagen."
Write-Host 'Sicherungskopien mit dem Suffix _orig liegen neben den Originalen.'
