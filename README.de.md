# scriptbox

Kleine PowerShell-Werkzeuge für alltägliche Aufgaben. Die derzeit dokumentierten Werkzeuge unterstützen OCR, Optimierung, Prüfung und Sicherungskopien von PDFs.

## PDF-Werkzeuge

Die [Anleitung für PDF-Werkzeuge](pdf/README.de.md) enthält Einrichtung, Beispiele, Abhängigkeiten und eine vollständige Liste der benutzerseitigen Schalter.

Verfügbare Werkzeuge:

- `Initialize-PdfProcessor.ps1` — prüft und installiert Abhängigkeiten für die PDF-Verarbeitung.
- `Optimize-ScannedPdfs.ps1` — verarbeitet gescannte PDFs, ergänzt bei Bedarf OCR, korrigiert die Seitenausrichtung und komprimiert PDFs optional.
- `Find-PdfsWithoutTextLayer.ps1` — findet PDFs mit fehlenden oder teilweise fehlenden Textebenen.
- `Clear-OriginalPdfBackups.ps1` — entfernt `_orig`-Sicherungen nur, wenn die zugehörige bearbeitete PDF vorhanden ist.

Führe die Skripte in PowerShell aus. Bei deutscher Windows-Anzeigesprache erscheinen deutsche Konsolentexte, sonst englische. `-EnglishOutput` erzwingt Englisch.

## Parameter und Schalter der PDF-Skripte

| Skript | Parameter und Schalter |
| --- | --- |
| `Initialize-PdfProcessor.ps1` | `-EnglishOutput`. Interne ausgeblendete Parameter: `-ElevatedChild`, `-RuntimePythonPath`. |
| `Optimize-ScannedPdfs.ps1` | `-InputPath <Pfad>`, `-Language <Codes>`, `-JpegQuality <1-100>`, `-GhostscriptDpi <50-1200>`, `-NoDeskew`, `-NoRotationOfPages`, `-ProcessDigitallyBornPdfs`, `-NoGhostscript`, `-ReplaceOriginal`, `-ForceReprocess`, `-EnglishOutput`. |
| `Find-PdfsWithoutTextLayer.ps1` | `-InputPath <Pfad>`, `-EnglishOutput`. |
| `Clear-OriginalPdfBackups.ps1` | `-InputPath <Ordner>`, `-WhatIf`, `-Confirm` (mit `-Confirm:$false` werden Rückfragen unterdrückt), `-EnglishOutput`. |

Die [PDF-Anleitung](pdf/README.de.md) beschreibt das Verhalten der Parameter, Beispiele, Einrichtung, Abhängigkeiten und Sicherheitsaspekte.

Die Verarbeitung gescannter PDFs verwendet eine bestmögliche zustandslose Klassifizierung: digital erzeugte PDFs werden standardmäßig übersprungen; neben der PDF wird kein dauerhafter Marker abgelegt. Gescannte PDFs mit vorhandener OCR werden automatisch erneut verarbeitet, damit Schräglagen- und Rotationskorrektur angewendet werden. Die OCR wird neu erzeugt und der Seiteninhalt gerastert. `-ProcessDigitallyBornPdfs` verarbeitet digital erzeugte PDFs ausdrücklich. Die Klassifizierung ist eine Heuristik und kann gemischte oder ungewöhnliche PDFs falsch einordnen.

Das Projekt steht unter der [MIT-Lizenz](LICENSE.md).
Hinweise zum Mitwirken stehen in [CONTRIBUTING.md](CONTRIBUTING.md).

## Dokumentation

- Englisch: [README.md](README.md)
- Deutsch: [README.de.md](README.de.md)
- PDF-Werkzeuge (Englisch): [pdf/README.md](pdf/README.md)
- PDF-Werkzeuge (Deutsch): [pdf/README.de.md](pdf/README.de.md)
