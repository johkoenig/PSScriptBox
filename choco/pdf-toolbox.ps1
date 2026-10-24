# PDF Toolbox: optimize scanned PDFs and add a searchable OCR text layer.
# Runs as a standard user; it never installs software or requests elevation itself.
# Dependencies (install separately, e.g. from elevated PowerShell):
#   choco install python tesseract ghostscript -y
#   py -m pip install --user ocrmypdf
# Usage: .\pdf-toolbox.ps1
# Backups with _orig are created once. Originals remain unchanged if processing fails.

$ErrorActionPreference = 'Stop'

function Find-CommandPath([string] $Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Show-SetupInstructions {
    Write-Host "`nFehlende Abhängigkeiten:" -ForegroundColor Yellow
    foreach ($item in $script:missing) { Write-Host "  - $item" }
    Write-Host "`nBitte in einer neuen PowerShell-Sitzung als Administrator installieren:"
    Write-Host '  choco install python tesseract ghostscript -y'
    Write-Host '  py -m pip install --user ocrmypdf'
    Write-Host 'Danach dieses Skript in einer normalen PowerShell erneut starten.'
}

$script:missing = @()
$python = Find-CommandPath 'py'
if (-not $python) { $python = Find-CommandPath 'python' }
if (-not $python) { $script:missing += 'Python (py.exe oder python.exe)' }
if (-not (Find-CommandPath 'tesseract')) { $script:missing += 'Tesseract' }
if (-not (Find-CommandPath 'gswin64c') -and -not (Find-CommandPath 'gswin32c') -and -not (Find-CommandPath 'gs')) {
    $script:missing += 'Ghostscript'
}

if ($python) {
    & $python -c "import ocrmypdf" 2>$null
    if ($LASTEXITCODE -ne 0) { $script:missing += 'OCRmyPDF (Python-Modul)' }
}

if ($script:missing.Count -gt 0) {
    Show-SetupInstructions
    exit 1
}

# Request one PDF file or a directory. Directory mode is non-recursive.
$target = Read-Host 'Pfad zu einer PDF-Datei oder einem Ordner mit PDFs eingeben'
$target = [Environment]::ExpandEnvironmentVariables($target.Trim().Trim('"'))
if (-not (Test-Path -LiteralPath $target)) {
    Write-Error "Pfad nicht gefunden: $target"
    exit 1
}

$item = Get-Item -LiteralPath $target
if ($item.PSIsContainer) {
    $pdfs = @(Get-ChildItem -LiteralPath $item.FullName -File -Filter '*.pdf')
} elseif ($item.Extension -ieq '.pdf') {
    $pdfs = @($item)
} else {
    Write-Error 'Die ausgewählte Datei hat keine .pdf-Endung.'
    exit 1
}

if ($pdfs.Count -eq 0) {
    Write-Host 'Keine PDFs gefunden.'
    exit 0
}

$language = Read-Host 'OCR-Sprachen (Tesseract-Codes, z.B. deu oder deu+eng) [deu]'
if ([string]::IsNullOrWhiteSpace($language)) { $language = 'deu' }

$ok = 0
$failed = 0
foreach ($pdf in $pdfs) {
    $backup = Join-Path $pdf.DirectoryName ($pdf.BaseName + '_orig' + $pdf.Extension)
    $temp = Join-Path $pdf.DirectoryName ([guid]::NewGuid().ToString() + '.pdf')

    try {
        if (-not (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $pdf.FullName -Destination $backup
        } else {
            Write-Host "Sicherung bereits vorhanden; wird nicht überschrieben: $backup" -ForegroundColor DarkYellow
        }

        Write-Host "Bearbeite: $($pdf.Name)"
        # --skip-text preserves pages with existing text; --optimize 3 attempts lossless
        # stream/image optimizations. OCRmyPDF writes to a temporary file so failures
        # do not replace the source PDF.
        & $python -m ocrmypdf --skip-text --optimize 3 --output-type pdf --language $language -- $pdf.FullName $temp
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temp)) {
            throw "OCRmyPDF meldete einen Fehler (Exitcode $LASTEXITCODE)."
        }

        $oldLength = (Get-Item -LiteralPath $pdf.FullName).Length
        $newLength = (Get-Item -LiteralPath $temp).Length
        if ($newLength -lt $oldLength) {
            Move-Item -LiteralPath $temp -Destination $pdf.FullName -Force
            Write-Host ("Fertig: {0:N1} MB -> {1:N1} MB" -f ($oldLength / 1MB), ($newLength / 1MB)) -ForegroundColor Green
        } else {
            Remove-Item -LiteralPath $temp -Force
            Write-Host 'Ergebnis wäre nicht kleiner; Original bleibt unverändert.' -ForegroundColor Yellow
        }
        $ok++
    } catch {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        Write-Warning "Fehler bei '$($pdf.Name)': $_"
        $failed++
    }
}

Write-Host "`nAbgeschlossen: $ok erfolgreich, $failed fehlgeschlagen. Sicherungen mit _orig liegen neben den Originalen."
