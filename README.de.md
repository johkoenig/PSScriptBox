# scriptbox

Kleine PowerShell-Werkzeuge für alltägliche Aufgaben. Die derzeit dokumentierten Werkzeuge unterstützen OCR, Optimierung, Prüfung und Sicherungskopien von PDFs.

## PDF-Werkzeuge

Die [Anleitung für PDF-Werkzeuge](pdf/README.de.md) enthält Einrichtung, Beispiele, Abhängigkeiten und eine vollständige Liste der benutzerseitigen Schalter.

Verfügbare Werkzeuge:

- `Initialize-PdfProcessor.ps1` — prüft und installiert Abhängigkeiten für die PDF-Verarbeitung.
- `Invoke-PdfOptimization.ps1` — fügt OCR-Textebenen hinzu oder erneuert sie, begradigt Seiten und komprimiert PDFs optional.
- `Find-PdfsWithoutTextLayer.ps1` — findet PDFs mit fehlenden oder teilweise fehlenden Textebenen.
- `Clear-OriginalPdfBackups.ps1` — entfernt `_orig`-Sicherungen nur, wenn die zugehörige bearbeitete PDF vorhanden ist.

Führe die Skripte in PowerShell aus. Bei deutscher Windows-Anzeigesprache erscheinen deutsche Konsolentexte, sonst englische. `-EnglishOutput` erzwingt Englisch.

## Parameter und Schalter der PDF-Skripte

| Skript | Parameter und Schalter |
| --- | --- |
| `Initialize-PdfProcessor.ps1` | `-EnglishOutput`. Interne ausgeblendete Parameter: `-ElevatedChild`, `-RuntimePythonPath`. |
| `Invoke-PdfOptimization.ps1` | `-InputPath <Pfad>`, `-Language <Codes>`, `-JpegQuality <1-100>`, `-GhostscriptDpi <50-1200>`, `-NoDeskew`, `-RotatePages`, `-NoGhostscript`, `-ReplaceOriginal`, `-RedoOcr`, `-ForceReprocess`, `-EnglishOutput`. |
| `Find-PdfsWithoutTextLayer.ps1` | `-InputPath <Pfad>`, `-EnglishOutput`. |
| `Clear-OriginalPdfBackups.ps1` | `-InputPath <Ordner>`, `-WhatIf`, `-Confirm` (mit `-Confirm:$false` werden Rückfragen unterdrückt), `-EnglishOutput`. |

Die [PDF-Anleitung](pdf/README.de.md) beschreibt das Verhalten der Parameter, Beispiele, Einrichtung, Abhängigkeiten und Sicherheitsaspekte.

Die PDF-Optimierung verwendet eine bestmögliche Idempotenz ohne Statusdateien: PDFs mit vollständiger Textebene werden standardmäßig übersprungen; neben der PDF wird kein dauerhafter Marker abgelegt. `-ForceReprocess` und `-RedoOcr` umgehen diesen Schutz ausdrücklich und können die PDF bei wiederholten Läufen erneut verändern.

Das Projekt steht unter der [MIT-Lizenz](LICENSE.md).

## Dokumentation

- Englisch: [README.md](README.md)
- Deutsch: [README.de.md](README.de.md)
- PDF-Werkzeuge (Englisch): [pdf/README.md](pdf/README.md)
- PDF-Werkzeuge (Deutsch): [pdf/README.de.md](pdf/README.de.md)
