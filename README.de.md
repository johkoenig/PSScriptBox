# scriptbox

Kleine PowerShell-Werkzeuge für alltägliche Aufgaben, darunter PDF-Verarbeitung, Git-Konfiguration sowie das Kopieren und Bereinigen lokaler Nextcloud-Daten.

## PDF-Werkzeuge

Die [Anleitung für PDF-Werkzeuge](pdf/README.de.md) enthält Einrichtung, Beispiele, Abhängigkeiten und eine vollständige Liste der benutzerseitigen Schalter.

Verfügbare Werkzeuge:

- `Initialize-PdfProcessor.ps1` — prüft und installiert Abhängigkeiten für die PDF-Verarbeitung.
- `Optimize-ScannedPdfs.ps1` — verarbeitet gescannte PDFs, ergänzt bei Bedarf OCR, korrigiert die Seitenausrichtung und komprimiert PDFs optional.
- `Find-PdfsWithoutTextLayer.ps1` — findet PDFs mit fehlenden oder teilweise fehlenden Textebenen.
- `Clear-OriginalPdfBackups.ps1` — entfernt `_orig`-Sicherungen nur, wenn die zugehörige bearbeitete PDF vorhanden ist.

Führe die Skripte in PowerShell aus. Bei deutscher Windows-Anzeigesprache erscheinen deutsche Konsolentexte, sonst englische. `-EnglishOutput` erzwingt Englisch.

## Git-Konfiguration

`git/Initialize-GitConfiguration.ps1` legt die Git-Autor-Identität (lokal oder global) fest, indem es gefundene Namen und E-Mail-Adressen (vorhandene Git-Einstellungen, Active-Directory-/Windows-Kontodaten, Microsoft-Konto) oder einen eigenen Wert zur Auswahl anbietet und empfohlene Standardeinstellungen einzeln bestätigen lässt. Vorhandene Werte sind jeweils der Standard; im Skript werden keine Identitätsdaten gespeichert. Parameter und Beispiele stehen in der [Git-Anleitung](git/README.de.md).

## Nextcloud-Dateikopie und lokale Bereinigung

Der Ablauf verwendet zwei Skripte: `nextcloud/Copy-UserDataToNextcloud.ps1` kopiert ausgewählte Windows-Benutzerordner in vorhandene Nextcloud-Zielordner und löscht niemals Quelldaten. Nach abgeschlossener Synchronisierung zum Server kann `nextcloud/Remove-MigratedUserData.ps1` lokale Dateien löschen, deren SHA-256-Hash mit einer Datei im zugeordneten Nextcloud-Zielordner übereinstimmt, sowie leere lokale Unterordner, wenn der entsprechende Nextcloud-Ordner existiert. Vor dem Löschen bestätigt der Benutzer die vollständige Synchronisierung und genehmigt die Bereinigung für jeden Hauptordner separat. Details und Beispiele stehen in der [Nextcloud-Anleitung](nextcloud/README.de.md).

## Parameter und Schalter der PDF-Skripte

| Skript | Parameter und Schalter |
| --- | --- |
| `Initialize-PdfProcessor.ps1` | `-EnglishOutput`. Interne ausgeblendete Parameter: `-ElevatedChild`, `-RuntimePythonPath`. |
| `Optimize-ScannedPdfs.ps1` | `-InputPath <Pfad>`, `-Language <Codes>`, `-JpegQuality <1-100>`, `-GhostscriptDpi <50-1200>`, `-NoDeskew`, `-NoRotationOfPages`, `-ProcessDigitallyBornPdfs`, `-NoGhostscript`, `-ReplaceOriginal`, `-ForceReprocess`, `-EnglishOutput`. |
| `Find-PdfsWithoutTextLayer.ps1` | `-InputPath <Pfad>`, `-EnglishOutput`. |
| `Clear-OriginalPdfBackups.ps1` | `-InputPath <Ordner>`, `-WhatIf`, `-Confirm` (mit `-Confirm:$false` werden Rückfragen unterdrückt), `-EnglishOutput`. |

Die [PDF-Anleitung](pdf/README.de.md) beschreibt das Verhalten der Parameter, Beispiele, Einrichtung, Abhängigkeiten und Sicherheitsaspekte.

## Parameter und Schalter der übrigen Werkzeuge

| Skript | Parameter und Schalter |
| --- | --- |
| `Initialize-GitConfiguration.ps1` | `-RepositoryPath <Pfad>`, `-Scope <Local\|Global>`, `-Name <Name>`, `-Email <Adresse>`, `-EnglishOutput`. |
| `Copy-UserDataToNextcloud.ps1` | `-NextcloudPath <Pfad>`, `-Folders <Namen>`, `-WhatIf`, `-Confirm`, `-EnglishOutput`. Kopiert nur; Quelldateien werden nicht gelöscht. |
| `Remove-MigratedUserData.ps1` | `-NextcloudPath <Pfad>`, `-Folders <Namen>`, `-WhatIf`, `-Confirm`, `-EnglishOutput`. Löscht lokale Dateien mit übereinstimmendem SHA-256-Hash und leere Unterordner, wenn der entsprechende Nextcloud-Ordner existiert. |

Die Verarbeitung gescannter PDFs verwendet eine bestmögliche zustandslose Klassifizierung: digital erzeugte PDFs werden standardmäßig übersprungen; neben der PDF wird kein dauerhafter Marker abgelegt. Gescannte PDFs mit vorhandener OCR werden automatisch erneut verarbeitet, damit Schräglagen- und Rotationskorrektur angewendet werden. Die OCR wird neu erzeugt und der Seiteninhalt gerastert. `-ProcessDigitallyBornPdfs` verarbeitet digital erzeugte PDFs ausdrücklich. Die Klassifizierung ist eine Heuristik und kann gemischte oder ungewöhnliche PDFs falsch einordnen.

Das Projekt steht unter der [MIT-Lizenz](LICENSE.md).
Hinweise zum Mitwirken stehen in [CONTRIBUTING.md](CONTRIBUTING.md).

## Dokumentation

- Englisch: [README.md](README.md)
- Deutsch: [README.de.md](README.de.md)
- PDF-Werkzeuge (Englisch): [pdf/README.md](pdf/README.md)
- PDF-Werkzeuge (Deutsch): [pdf/README.de.md](pdf/README.de.md)
- Git tool (English): [git/README.md](git/README.md)
- Git-Werkzeug (Deutsch): [git/README.de.md](git/README.de.md)
- Nextcloud tool (English): [nextcloud/README.md](nextcloud/README.md)
- Nextcloud-Werkzeug (Deutsch): [nextcloud/README.de.md](nextcloud/README.de.md)
