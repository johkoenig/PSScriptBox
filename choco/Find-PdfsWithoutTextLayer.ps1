<#
.SYNOPSIS
    Findet PDF-Dateien ohne durchsuchbare Textebene.

.DESCRIPTION
    Prüft eine PDF-Datei oder alle PDFs in einem Ordner einschließlich Unterordnern.
    Erkannt werden PDF-Textoperatoren in Seiteninhalten und eingebetteten Formularen.
    Dateien ohne Textoperatoren sowie PDFs mit nur teilweise vorhandenen Textinhalten
    werden getrennt aufgelistet. Das Skript bewertet nicht die Qualität oder
    Durchsuchbarkeit erkannter Textinhalte. Der Dateiinhalt wird nicht verändert.

.PARAMETER InputPath
    PDF-Datei oder Ordner, der rekursiv nach PDF-Dateien durchsucht werden soll.
    Ohne Angabe wird der Pfad interaktiv abgefragt.

.EXAMPLE
    .\Find-PdfsWithoutTextLayer.ps1 -InputPath 'C:\PDFs'
    Prüft alle PDFs in C:\PDFs und dessen Unterordnern.

.EXAMPLE
    .\Find-PdfsWithoutTextLayer.ps1 -InputPath 'C:\PDFs\Scan.pdf'
    Prüft nur die angegebene PDF-Datei.

.NOTES
    Abhängigkeiten: PowerShell 5.1 oder neuer, Python und das Python-Modul pikepdf.
    Installation des Moduls: py -m pip install --user pikepdf
    (alternativ: python -m pip install --user pikepdf)
    Es werden keine Dateien verändert und keine Administratorrechte benötigt.
#>

[CmdletBinding()]
param(
    [string] $InputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Wandelt ein Argument für ProcessStartInfo.Arguments in eine Windows-konforme
# zitierte Zeichenfolge um.
# Rückgabe: Das sicher zitierte Argument.
function ConvertTo-QuotedArgument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Value)

    $escaped = [regex]::Replace($Value, '(\\)(?=")', '$1$1')
    if ($escaped.EndsWith('\')) { $escaped += '\' }
    $escaped = $escaped -replace '"', '\"'
    return '"' + $escaped + '"'
}

# Startet Python mit umgeleiteten und asynchron gelesenen Streams, damit Fehler
# zuverlässig ausgewertet werden und größere Ausgaben keine Pipe blockieren.
# Parameter: Python- und Argumentliste für den Prozess.
# Rückgabe: Exitcode, Standardausgabe und Fehlerausgabe.
function Invoke-PythonCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $PythonPath,
        [Parameter(Mandatory)][string[]] $Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $PythonPath
    $startInfo.Arguments = ($Arguments | ForEach-Object { ConvertTo-QuotedArgument -Value $_ }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Python konnte nicht gestartet werden: $PythonPath"
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdoutTask.GetAwaiter().GetResult()
            StdErr   = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

# Ermittelt PDFs ohne Textoperatoren und PDFs mit nur teilweise textfähigen Seiten.
# Parameter: PDF-Pfad und Python-Pfad.
# Rückgabe: Anzahl Seiten, Anzahl Seiten mit Textoperatoren und Prüfstatus.
function Get-PdfTextLayerStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo] $Pdf,
        [Parameter(Mandatory)][string] $PythonPath
    )

    $pythonCode = @'
import sys
import pikepdf

TEXT_OPERATORS = {"Tj", "TJ", "'", '"'}

def object_key(obj):
    try:
        object_number, generation = obj.objgen
        if object_number:
            return (object_number, generation)
    except (AttributeError, TypeError):
        pass
    return id(obj)

def inherited_resources(page):
    node = page
    while node is not None:
        resources = node.get("/Resources")
        if resources is not None:
            return resources
        node = node.get("/Parent")
    return pikepdf.Dictionary()

def stream_has_text(stream, resources, visited):
    key = object_key(stream)
    if key in visited:
        return False
    visited.add(key)

    xobjects = resources.get("/XObject", {})
    for operands, operator in pikepdf.parse_content_stream(stream):
        if str(operator) in TEXT_OPERATORS:
            return True
        if str(operator) == "Do" and operands:
            child = xobjects.get(operands[0])
            if child is not None and str(child.get("/Subtype")) == "/Form":
                child_resources = child.get("/Resources", resources)
                if stream_has_text(child, child_resources, visited):
                    return True
    return False

try:
    with pikepdf.open(sys.argv[1]) as pdf:
        text_pages = 0
        for page in pdf.pages:
            resources = inherited_resources(page.obj)
            if stream_has_text(page, resources, set()):
                text_pages += 1
        print(f"{len(pdf.pages)}\t{text_pages}")
except Exception as error:
    message = str(error)
    input_path = sys.argv[1]
    if message.lower().startswith(input_path.lower()):
        message = message[len(input_path):].lstrip(": ")
    print(f"{type(error).__name__}: {message}", file=sys.stderr)
    sys.exit(1)
'@

    $result = Invoke-PythonCommand -PythonPath $PythonPath -Arguments @('-c', $pythonCode, $Pdf.FullName)
    if ($result.ExitCode -ne 0) {
        $details = $result.StdErr.Trim()
        if (-not $details) { $details = $result.StdOut.Trim() }
        throw "PDF-Prüfung fehlgeschlagen (Exitcode $($result.ExitCode)): $details"
    }

    $values = $result.StdOut.Trim() -split "`t"
    if ($values.Count -ne 2 -or $values[0] -notmatch '^\d+$' -or $values[1] -notmatch '^\d+$') {
        throw "Python lieferte ein ungültiges Prüfergebnis für '$($Pdf.FullName)'."
    }

    $pageCount = [int]$values[0]
    $textPageCount = [int]$values[1]
    if ($pageCount -eq 0) {
        throw 'Die PDF-Datei enthält keine Seiten.'
    }

    $status = if ($textPageCount -eq 0) {
        'Ohne Textebene'
    }
    elseif ($textPageCount -lt $pageCount) {
        'Teilweise ohne Textebene'
    }
    else {
        'Textebene vorhanden'
    }

    return [pscustomobject]@{
        FilePath      = $Pdf.FullName
        PageCount     = $pageCount
        TextPageCount = $textPageCount
        Status        = $status
        Error         = $null
    }
}

# --- Eingabe und Abhängigkeiten ------------------------------------------

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    Write-Host 'Pfad zu einer PDF-Datei oder einem Ordner mit PDFs eingeben.'
    $InputPath = Read-Host 'InputPath'
}
$InputPath = [Environment]::ExpandEnvironmentVariables($InputPath.Trim().Trim('"'))
if ([string]::IsNullOrWhiteSpace($InputPath)) {
    throw 'Es wurde kein Pfad angegeben.'
}

$pythonCommand = Get-Command -Name 'py' -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -eq $pythonCommand) {
    $pythonCommand = Get-Command -Name 'python' -ErrorAction SilentlyContinue |
        Select-Object -First 1
}
if ($null -eq $pythonCommand) {
    Write-Host 'Fehlende Abhängigkeit: Python (py.exe oder python.exe).' -ForegroundColor Yellow
    Write-Host 'Installation: https://www.python.org/downloads/'
    exit 1
}
$pythonPath = $pythonCommand.Source

$moduleCheck = Invoke-PythonCommand -PythonPath $pythonPath -Arguments @('-c', 'import pikepdf')
if ($moduleCheck.ExitCode -ne 0) {
    Write-Host 'Fehlende Abhängigkeit: Python-Modul pikepdf.' -ForegroundColor Yellow
    if ([System.IO.Path]::GetFileNameWithoutExtension($pythonPath) -ieq 'py') {
        Write-Host 'Installation: py -m pip install --user pikepdf'
    }
    else {
        Write-Host 'Installation: python -m pip install --user pikepdf'
    }
    exit 1
}

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Der angegebene Pfad wurde nicht gefunden: $InputPath"
}

$inputItem = Get-Item -LiteralPath $InputPath
if ($inputItem -is [System.IO.DirectoryInfo]) {
    $baseDirectory = $inputItem.FullName
    $pdfFiles = @(Get-ChildItem -LiteralPath $baseDirectory -File -Recurse -Filter '*.pdf' |
        Sort-Object -Property FullName)
}
elseif ($inputItem -is [System.IO.FileInfo] -and $inputItem.Extension -ieq '.pdf') {
    $baseDirectory = $inputItem.DirectoryName
    $pdfFiles = @($inputItem)
}
else {
    throw "Der Pfad muss auf eine PDF-Datei oder einen Ordner zeigen: $InputPath"
}

if ($pdfFiles.Count -eq 0) {
    Write-Host 'Keine PDFs gefunden.' -ForegroundColor Green
    exit 0
}

$basePathPrefix = $baseDirectory
if (-not $basePathPrefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar)) {
    $basePathPrefix += [System.IO.Path]::DirectorySeparatorChar
}

# --- PDFs prüfen ---------------------------------------------------------

Write-Host ''
Write-Host '       .-----------------------------------------------.' -ForegroundColor Cyan
Write-Host '       |  +----------------+                           |' -ForegroundColor Cyan
Write-Host '       |  |  PDF  ->  Text |   FIND PDFS WITHOUT TEXT  |' -ForegroundColor Cyan
Write-Host '       |  +----------------+                           |' -ForegroundColor Cyan
Write-Host '       ''-----------------------------------------------''' -ForegroundColor Cyan
Write-Host "  Ordner: $baseDirectory"
Write-Host "  Zu prüfende PDFs: $($pdfFiles.Count)"

$results = @(
    for ($index = 0; $index -lt $pdfFiles.Count; $index++) {
        $pdf = $pdfFiles[$index]
        $relativePath = $pdf.FullName.Substring($basePathPrefix.Length)
        Write-Host ''
        Write-Host ('--- PDF {0}/{1}: {2} ---' -f ($index + 1), $pdfFiles.Count, $relativePath) -ForegroundColor Cyan
        try {
            $result = Get-PdfTextLayerStatus -Pdf $pdf -PythonPath $pythonPath
            switch ($result.Status) {
                'Ohne Textebene' {
                    Write-Host 'Keine Textebene gefunden.' -ForegroundColor Yellow
                }
                'Teilweise ohne Textebene' {
                    Write-Host ('Textebene nur auf {0} von {1} Seiten gefunden.' -f $result.TextPageCount, $result.PageCount) -ForegroundColor DarkYellow
                }
                default {
                    Write-Host ('Textebene auf allen {0} Seiten gefunden.' -f $result.PageCount) -ForegroundColor Green
                }
            }
            $result
        }
        catch {
            Write-Warning "PDF konnte nicht geprüft werden: '$relativePath'`n$($_.Exception.Message)"
            [pscustomobject]@{
                FilePath      = $pdf.FullName
                PageCount     = 0
                TextPageCount = 0
                Status        = 'Fehler'
                Error         = $_.Exception.Message
            }
        }
    }
)

# --- Zusammenfassung -----------------------------------------------------

$withoutText = @($results | Where-Object { $_.Status -eq 'Ohne Textebene' })
$partialText = @($results | Where-Object { $_.Status -eq 'Teilweise ohne Textebene' })
$withText = @($results | Where-Object { $_.Status -eq 'Textebene vorhanden' })
$errors = @($results | Where-Object { $_.Status -eq 'Fehler' })

Write-Host ''
Write-Host '=== Zusammenfassung ===' -ForegroundColor Cyan
Write-Host ('Geprüft: {0}, ohne Textebene: {1}, teilweise: {2}, mit Textebene: {3}, Fehler: {4}' -f `
    $results.Count, $withoutText.Count, $partialText.Count, $withText.Count, $errors.Count)

Write-Host ''
Write-Host 'PDFs ohne Textebene:' -ForegroundColor Cyan
if ($withoutText.Count -eq 0) {
    Write-Host '  Keine.'
}
else {
    foreach ($result in $withoutText) {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        Write-Host "  - $relativePath ($($result.PageCount) Seiten)" -ForegroundColor Yellow
    }
}

if ($partialText.Count -gt 0) {
    Write-Host ''
    Write-Host 'PDFs mit teilweise fehlender Textebene:' -ForegroundColor Cyan
    foreach ($result in $partialText) {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        $pagesWithoutText = $result.PageCount - $result.TextPageCount
        Write-Host "  - $relativePath ($pagesWithoutText von $($result.PageCount) Seiten ohne Text)" -ForegroundColor DarkYellow
    }
}

if ($errors.Count -gt 0) {
    Write-Host ''
    Write-Host 'Nicht prüfbare PDFs:' -ForegroundColor Cyan
    foreach ($result in $errors) {
        $relativePath = $result.FilePath.Substring($basePathPrefix.Length)
        Write-Host "  - $relativePath ($($result.Error))" -ForegroundColor Red
    }
}
