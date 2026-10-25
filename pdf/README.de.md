# PDF-PowerShell-Werkzeuge

Dieser Ordner enthält PowerShell-Werkzeuge zum Einrichten und Verarbeiten von PDF-Dateien. Verwende Windows PowerShell 5.1 oder PowerShell 7 und starte die Skripte in einer normalen Benutzersitzung, sofern ein Skript nicht ausdrücklich Administratorrechte anfordert.

## Schnellstart

1. Öffne PowerShell in diesem Ordner.
2. Starte die Einrichtung der Abhängigkeiten:

   ```powershell
   .\Setup-PdfProcessor.ps1
   ```

3. Beachte Hinweise zu fehlenden Tesseract-Sprachdaten. Das Setup lädt keine `.traineddata`-Dateien herunter.
4. Verarbeite PDFs, zum Beispiel:

   ```powershell
   .\Invoke-PdfOptimization.ps1 -InputPath 'C:\PDFs'
   ```

Die PowerShell-Ausführungsrichtlinie kann eine genehmigte Vorgehensweise zum Ausführen lokaler Skripte erfordern. Ändere die systemweite Richtlinie nicht allein für diese Werkzeuge.

## Abhängigkeiten einrichten

`Setup-PdfProcessor.ps1` setzt eine separat installierte Chocolatey-Installation voraus. Es prüft Chocolatey, Python, OCRmyPDF, pikepdf, Tesseract und Ghostscript einzeln.

- Fehlende systemweite Programme werden über Chocolatey installiert.
- Das Setup bevorzugt einen funktionierenden Python-Interpreter im Profil des aktuellen Benutzers; andernfalls wählt es einen funktionierenden systemweiten Interpreter.
- `py.exe` dient nur dazu, einen konkreten `python.exe`-Pfad zu ermitteln. Die Skripte starten anschließend diesen Interpreter direkt.
- Fehlende Python-Pakete werden in der ausgewählten Python-Installation installiert. Für einen systemweiten Interpreter sind Administratorrechte erforderlich.
- Vor dem UAC-Dialog listet das Setup die geplanten Aktionen auf und wartet auf Enter. Jede nicht leere Eingabe bricht ab.
- Tesseract-Sprachdaten werden geprüft, aber nicht heruntergeladen. Die Standardsprachen sind `deu+eng+fra+ita+spa`; `deu` und `eng` sind erforderlich.

## Skripte und Schalter

### `Setup-PdfProcessor.ps1`

Prüft Abhängigkeiten, installiert fehlende Software und meldet fehlende Tesseract-Sprachdaten.

| Parameter / Schalter | Beschreibung |
| --- | --- |
| `-EnglishOutput` | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache. |

Die ausgeblendeten Parameter `-ElevatedChild` und `-RuntimePythonPath` sind interne Implementierungsdetails und nicht zur direkten Verwendung vorgesehen.

Beispiele:

```powershell
.\Setup-PdfProcessor.ps1
.\Setup-PdfProcessor.ps1 -EnglishOutput
```

### `Invoke-PdfOptimization.ps1`

Verarbeitet eine PDF-Datei oder alle PDFs eines Ordnerbaums. OCRmyPDF ergänzt bei Bedarf eine Textebene und begradigt schiefe Scans. Nach erfolgreicher Verarbeitung wird die Eingabedatei ersetzt; standardmäßig wird vorher eine Sicherung `<Name>_orig.pdf` erstellt. Existiert diese Sicherung bereits, bleibt sie erhalten und die Eingabedatei wird ohne Überschreiben der Sicherung ersetzt.

| Parameter / Schalter | Beschreibung |
| --- | --- |
| `-InputPath <Pfad>` | PDF-Datei oder Ordner. Ohne Angabe wird der Pfad abgefragt. |
| `-Language <Codes>` | Tesseract-Sprachen, getrennt durch `+`. Standard: `deu+eng+fra+ita+spa`; `deu` und `eng` sind erforderlich. |
| `-JpegQuality <1-100>` | JPEG-Qualität eingebetteter Bilder. Standard: `75`. |
| `-GhostscriptDpi <50-1200>` | Aktiviert Ghostscript-Downsampling mit der angegebenen DPI-Auflösung. Standard: deaktiviert (`0`). |
| `-NoDeskew` | Deaktiviert die standardmäßig aktive Begradigung. |
| `-RotatePages` | Aktiviert Erkennung und Korrektur verdrehter Seiten. Standard: deaktiviert. |
| `-NoGhostscript` | Deaktiviert den optionalen Ghostscript-Schritt. |
| `-ReplaceOriginal` | Ersetzt die Eingabe, ohne eine neue `_orig`-Sicherung anzulegen. |
| `-RedoOcr` | Verarbeitet vorhandene OCR-Textebene mit OCRmyPDF `--redo-ocr` erneut; die gesamte Seite wird dabei nicht gerastert. |
| `-ForceReprocess` | Umgeht das standardmäßige Überspringen von PDFs mit vollständiger Textebene. Wiederholte erzwungene Läufe können die PDF erneut verändern. |
| `-EnglishOutput` | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache. |

Beispiele:

```powershell
.\Invoke-PdfOptimization.ps1
.\Invoke-PdfOptimization.ps1 -InputPath 'C:\PDFs' -RotatePages -GhostscriptDpi 150
.\Invoke-PdfOptimization.ps1 -InputPath 'C:\PDFs\Scan.pdf' -RedoOcr -ReplaceOriginal
.\Invoke-PdfOptimization.ps1 -InputPath 'C:\PDFs' -ForceReprocess
.\Invoke-PdfOptimization.ps1 -InputPath 'C:\PDFs' -Language 'deu+eng' -EnglishOutput
```

PDFs mit vollständiger Textebene werden standardmäßig übersprungen, ohne sie erneut zu schreiben. So werden wiederholte Verarbeitungsläufe vermieden, ohne eine dauerhafte Zusatzdatei zu speichern. Mit `-ForceReprocess` wird die Optimierung trotzdem ausgeführt; `-RedoOcr` erneuert die vorhandene OCR-Textebene. Diese ausdrücklichen Optionen können die PDF bei wiederholten Läufen erneut verändern; Idempotenz ist dann nicht garantiert. Signierte PDFs und verschlüsselte PDFs, die sich nicht ohne Passwort öffnen lassen, werden übersprungen. Das Ergebnis ist eine normale PDF und kein PDF/A. Ghostscript läuft nur, wenn `-GhostscriptDpi` angegeben wurde.

### `Find-PdfsWithoutTextLayer.ps1`

Meldet PDFs ohne Textoperatoren und PDFs, bei denen nur einige Seiten Textoperatoren enthalten. Die OCR-Qualität wird nicht bewertet; Dateien werden nicht verändert.

| Parameter / Schalter | Beschreibung |
| --- | --- |
| `-InputPath <Pfad>` | PDF-Datei oder rekursiv zu prüfender Ordner. Ohne Angabe wird der Pfad abgefragt. |
| `-EnglishOutput` | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache. |

Beispiele:

```powershell
.\Find-PdfsWithoutTextLayer.ps1 -InputPath 'C:\PDFs'
.\Find-PdfsWithoutTextLayer.ps1 -InputPath 'C:\PDFs\Scan.pdf' -EnglishOutput
```

### `Clean-OriginalPdfs.ps1`

Findet `_orig.pdf`-Sicherungen, zu denen die bearbeitete PDF im selben Ordner vorhanden ist. Jede Löschung unterliegt dem Bestätigungsverhalten von PowerShell.

| Parameter / Schalter | Beschreibung |
| --- | --- |
| `-InputPath <Ordner>` | Rekursiv zu durchsuchender Ordner. Ohne Angabe wird der Pfad abgefragt. |
| `-WhatIf` | Zeigt geplante Löschungen an, ohne Dateien zu löschen. |
| `-Confirm` | Fragt vor jeder Löschung nach. Dies ist wegen der hohen Auswirkung standardmäßig aktiv; `-Confirm:$false` unterdrückt Rückfragen. |
| `-EnglishOutput` | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache. |

Beispiele:

```powershell
.\Clean-OriginalPdfs.ps1 -InputPath 'C:\PDFs' -WhatIf
.\Clean-OriginalPdfs.ps1 -InputPath 'C:\PDFs' -Confirm:$false
.\Clean-OriginalPdfs.ps1 -InputPath 'C:\PDFs' -EnglishOutput
```

## Gemeinsame PowerShell-Parameter

Skripte unterstützen, soweit anwendbar, außerdem PowerShell-Standardparameter wie `-Verbose`, `-Debug`, `-ErrorAction` und `-WarningAction`. `Clean-OriginalPdfs.ps1` unterstützt über `SupportsShouldProcess` auch `-WhatIf` und `-Confirm`.

## Sicherheit und Verhalten

- `Invoke-PdfOptimization.ps1` legt temporäre Dateien neben der Eingabe an und entfernt sie nach der Verarbeitung.
- Neben der PDF werden keine dauerhaften Status- oder Markierungsdateien angelegt. Temporäre Verarbeitungsdateien werden nach dem Lauf entfernt.
- Eine vollständige Textebene dient als zustandsloses Indiz dafür, dass OCR bereits angewendet wurde; solche PDFs werden übersprungen, außer `-ForceReprocess` oder `-RedoOcr` wird verwendet. Das ist eine bestmögliche Idempotenz: Bei einer digital erzeugten PDF lässt sich damit nicht erkennen, ob eine Bildoptimierung gewünscht ist.
- Eine PDF gilt nur dann als erfolgreich verändert, wenn die Verarbeitung erfolgreich war und sich der Ergebnis-Hash von der Originaldatei unterscheidet. Auch größere Ergebnisse können gültig sein.
- Vorhandene `_orig`-Sicherungen bleiben erhalten.
- `Clean-OriginalPdfs.ps1` löscht nur Sicherungen, zu denen die bearbeitete PDF vorhanden ist.
- Verwende diese Werkzeuge nicht für Dateien, die byte-identisch bleiben müssen, etwa digital signierte PDFs.
- Das Projekt steht unter der [MIT-Lizenz](../LICENSE.md).

## Weitere Dokumentation

- Repository-Übersicht (Englisch): [../README.md](../README.md)
- Repository-Übersicht (Deutsch): [../README.de.md](../README.de.md)
- PDF-Werkzeuge (Englisch): [README.md](README.md)
