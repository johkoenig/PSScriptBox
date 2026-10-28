# scriptbox

> Englische Version: [README.md](README.md)

> [!CAUTION]
> 🔴 **ALPHA: Dieses Projekt befindet sich im Alpha-Stadium. Die Skripte NICHT auf produktiven Daten ausführen.** Nur mit Kopien der Dateien testen und Sicherungen anlegen.

Kleine PowerShell-Werkzeuge für alltägliche Aufgaben, darunter PDF-Verarbeitung, Git-Konfiguration sowie das Kopieren und Bereinigen lokaler Nextcloud-Daten.

## PDF-Werkzeuge

Verfügbare Werkzeuge:

- `Initialize-PdfProcessor.ps1` — prüft und installiert Abhängigkeiten für die PDF-Verarbeitung.
- `ConvertTo-SearchablePdf.ps1` — ergänzt OCR und korrigiert gescannte Seiten; digital erzeugte PDFs werden
  übersprungen, verschlüsselte und signierte PDFs als Probleme gemeldet.
- `Optimize-PdfSize.ps1` — skaliert Bilder zur Größenreduzierung herunter; Standardziel sind 300 DPI und JPEG-Qualität
  75; Originale unter 1 MB werden übersprungen.
- `Find-PdfsWithoutTextLayer.ps1` — findet PDFs mit fehlenden oder teilweise fehlenden Textebenen.
- `Remove-PdfBackups.ps1` — entfernt `_orig`-Sicherungen nur, wenn die zugehörige bearbeitete PDF vorhanden ist.
- `Restore-PdfOriginals.ps1` — ersetzt bearbeitete PDFs durch passende `_orig`-Originale.

| Skript                          | Parameter und Schalter                                                                                                                                                                          |
|---------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Initialize-PdfProcessor.ps1`   | `-EnglishOutput`. Interne ausgeblendete Parameter: `-ElevatedChild`, `-RuntimePythonPath`.                                                                                                      |
| `ConvertTo-SearchablePdf.ps1`   | `-InputPath <Pfad>`, `-Language <Codes>`, `-NoDeskew`, `-NoRotationOfPages`, `-ReplaceOriginal`, `-EnglishOutput`.                                                                              |
| `Optimize-PdfSize.ps1`          | `-InputPath <Pfad>`, `-Dpi <50-1200>` (Standard `300`), `-JpegQuality <1-100>` (Standard `75`), `-MinFileSize <Bytes>` (Standard `1MB`; `0` deaktiviert), `-ReplaceOriginal`, `-EnglishOutput`. |
| `Find-PdfsWithoutTextLayer.ps1` | `-InputPath <Pfad>`, `-EnglishOutput`.                                                                                                                                                          |
| `Remove-PdfBackups.ps1`         | `-InputPath <Ordner>`, `-WhatIf`, `-Confirm` (mit `-Confirm:$false` werden Rückfragen unterdrückt), `-EnglishOutput`.                                                                           |
| `Restore-PdfOriginals.ps1`      | `-InputPath <Ordner>`, `-WhatIf`, `-Confirm` (mit `-Confirm:$false` werden Rückfragen unterdrückt), `-EnglishOutput`.                                                                           |

Die OCR-Verarbeitung gescannter PDFs verwendet eine bestmögliche zustandslose Klassifizierung: digital erzeugte PDFs
werden übersprungen; neben der PDF wird kein dauerhafter Marker abgelegt. Gescannte PDFs mit vorhandener OCR werden
nicht erneut mit OCR verarbeitet; vorhandener Text bleibt erhalten. Seitenrotationen werden separat erkannt und
korrigiert, ohne die Textebene neu zu erzeugen. Bei teilweise erkannten Scans wird OCR nur für Seiten ohne Text ergänzt.
Für die Rotationserkennung auf Seiten mit vorhandener Textebene wird Ghostscript benötigt. Die Größenoptimierung ist
ein separater Schritt und verarbeitet auch digital erzeugte PDFs. Bei Ordnern ermittelt die Größenoptimierung zuerst
alle PDFs und verarbeitet nur Dateien, die mindestens die Mindestgröße erreichen. Verschlüsselte und digital signierte
PDFs können nicht verarbeitet werden und erscheinen in der Problemliste. Regulär übersprungene und unveränderte
Dateien werden in der Zusammenfassung gezählt, aber nicht einzeln aufgeführt.

Die [PDF-Anleitung](pdf/README.de.md) beschreibt das Verhalten der Parameter, Beispiele, Einrichtung, Abhängigkeiten und Sicherheitsaspekte.

Führe die Skripte in PowerShell aus. Bei deutscher Windows-Anzeigesprache erscheinen deutsche Konsolentexte, sonst englische. `-EnglishOutput` erzwingt Englisch.

## Medienwerkzeuge

`media/Optimize-MediaSize.ps1` kodiert geeignete `.mov`- und `.mp4`-Videos als 720p-H.265/HEVC-MP4 mit einer
durchschnittlichen Video-Bitrate von 1,9 Mb/s und 96 kb/s Audio. Querformat wird auf 1280x720 und Hochformat auf
720x1280 begrenzt; ein sechsminütiges Video zielt auf ungefähr 90 MB, die tatsächliche Größe variiert jedoch. H.264 bis
einschließlich 1,9 Mb/s sowie HEVC-, AV1- und VP9-Quelldateien werden übersprungen.
JPEG-Fotos über 6 MB werden proportional auf eine geschätzte Ausgabegröße von 5 MB verkleinert und mit hoher Qualität
neu kodiert; die tatsächliche Größe hängt von den Bilddetails ab. Kleinere Fotos werden übersprungen.
Ergebnisse werden nur übernommen, wenn sie kleiner sind; unterstützte Dateizeitstempel sowie eingebettete EXIF-/XMP-
und Container-Aufnahmedaten werden vor dem Ersetzen geprüft. Erstellungs- und Änderungszeiten einzelner Tracks werden
nicht verglichen. Der interne Samsung-Maker-Note-Zeitstempel `TimeStamp` und das nicht aufnahmerelevante EXIF-Feld
`IFD0:ModifyDate` werden ebenfalls nicht verglichen.
Standardmäßig wird das Original als `<Name>_orig` mit seiner ursprünglichen Erweiterung gesichert.
Die Kodierung ist verlustbehaftet und kann keine unmerkliche Qualitätsänderung garantieren. FFmpeg (einschließlich
FFprobe) mit `libx265`- und MJPEG-Encodern sowie ExifTool müssen über `PATH` verfügbar sein.
`media/Remove-MediaBackups.ps1` entfernt interaktiv `_orig`-Sicherungen nur, wenn die bearbeitete Datei vorhanden ist;
eine MOV-Sicherung wird der MP4-Ausgabe zugeordnet.
`media/Remove-LivePhotos.ps1` entfernt ein MOV-Video nur, wenn im selben Ordner ein gleichnamiges JPG-Foto vorhanden
ist;
das JPG bleibt erhalten und `.jpeg` gilt nicht als Treffer. Das Skript unterstützt `-WhatIf` und fragt vor jeder
Löschung nach.

`media/Restore-MediaDate.ps1` stellt Datumsangaben in dieser Reihenfolge wieder her: Dateiname, EXIF
`DateTimeOriginal`, `CreateDate`, dann `ModifyDate`. Das Skript benennt unterstützte Mediendateien nach
`YY-MM-DD HH-mm-ss XXXX.ext` um, aktualisiert Erstellungs- und Änderungszeit sowie unterstützte eingebettete Daten
nur dann, wenn sie vom ausgewählten Datum abweichen, und bietet mit `-WhatIf` eine Vorschau. Namen, die bereits dem
Muster entsprechen, bleiben erhalten. ExifTool muss über `PATH` verfügbar sein; Windows erlaubt keine Änderung der
niedrigstufigen NTFS-Änderungszeit.

| Skript                    | Parameter und Schalter                                                            |
|---------------------------|-----------------------------------------------------------------------------------|
| `Optimize-MediaSize.ps1`  | `-InputPath <Pfad>`, `-ReplaceOriginal`, `-WhatIf`, `-Confirm`, `-EnglishOutput`. |
| `Remove-MediaBackups.ps1` | `-InputPath <Ordner>`, `-WhatIf`, `-Confirm`, `-EnglishOutput`.                   |
| `Remove-LivePhotos.ps1`   | `-InputPath <Ordner>`, `-WhatIf`, `-Confirm`, `-EnglishOutput`.                   |
| `Restore-MediaDate.ps1`   | `-InputPath <Ordner>`, `-WhatIf`, `-Confirm`, `-EnglishOutput`.                   |

Die [Anleitung zu den Medienwerkzeugen](media/README.de.md) enthält Beispiele, Abhängigkeiten und Einschränkungen beim
Erhalt von Datumsangaben.

## Tests

Der GitHub-Actions-Workflow führt `tests/Invoke-Tests.ps1` bei Pull Requests mit Ziel `main` unter Windows PowerShell 5.1 und PowerShell 7 aus. Dieselbe Testsuite lässt sich lokal im Repository-Stamm mit `.\tests\Invoke-Tests.ps1` starten; erforderlich ist Pester 5 oder höher.

## Git-Werkzeuge

`git/Initialize-GitConfiguration.ps1` legt die Git-Autor-Identität (lokal oder global) fest, indem es gefundene Namen und E-Mail-Adressen (vorhandene Git-Einstellungen, Active-Directory-/Windows-Kontodaten, Microsoft-Konto) oder einen eigenen Wert zur Auswahl anbietet und empfohlene Standardeinstellungen einzeln bestätigen lässt. Vorhandene Werte sind jeweils der Standard; im Skript werden keine Identitätsdaten gespeichert.

`git/Remove-ObsoleteGitBranches.ps1` entfernt veraltete lokale Branches aus dem Repository am aktuellen Speicherort.
`main` und der aktuelle Branch bleiben geschützt; Dateien im Arbeitsbereich werden nicht verändert. Ohne `-WhatIf`
werden Kandidaten sofort und ohne Rückfrage entfernt; `-WhatIf` zeigt sie als Vorschau an.

| Skript                            | Parameter und Schalter                                                                                    |
|-----------------------------------|-----------------------------------------------------------------------------------------------------------|
| `Initialize-GitConfiguration.ps1` | `-RepositoryPath <Pfad>`, `-Scope <Local\|Global>`, `-Name <Name>`, `-Email <Adresse>`, `-EnglishOutput`. |
| `Remove-ObsoleteGitBranches.ps1`  | `-WhatIf`, `-EnglishOutput`.                                                                              |

Ein Branch ist ein Kandidat, wenn er nicht weiter als der lokale `main`-Branch oder sein verfügbarer Upstream ist oder
vollständig in den aktuell ausgecheckten Branch integriert wurde. Die Bereinigung verwendet nur lokale Referenzen; mit
`-WhatIf` kann sie vorab angezeigt werden.

Parameter und Beispiele stehen in der [Git-Anleitung](git/README.de.md).

## Nextcloud-Dateikopie und lokale Bereinigung

Der Ablauf verwendet zwei Skripte: `nextcloud/Copy-UserDataToNextcloud.ps1` kopiert ausgewählte Windows-Benutzerordner
in vorhandene Nextcloud-Zielordner und löscht niemals Quelldaten. Dateiübertragungen werden in `.part`-Dateien
zwischengespeichert und erst nach Abschluss unter den endgültigen Namen verschoben. Nach abgeschlossener
Synchronisierung zum Server kann `nextcloud/Remove-MigratedUserData.ps1` lokale Dateien löschen, deren SHA-256-Hash mit
einer Datei im zugeordneten Nextcloud-Zielordner übereinstimmt, sowie leere lokale Unterordner, wenn der entsprechende
Nextcloud-Ordner existiert. Vor dem Löschen bestätigt der Benutzer die vollständige Synchronisierung und genehmigt die
Bereinigung für jeden Hauptordner separat.

| Skript | Parameter und Schalter |
| --- | --- |
| `Copy-UserDataToNextcloud.ps1` | `-NextcloudPath <Pfad>`, `-Folders <Namen>`, `-WhatIf`, `-Confirm`, `-EnglishOutput`. Kopiert nur; Quelldateien werden nicht gelöscht. |
| `Remove-MigratedUserData.ps1` | `-NextcloudPath <Pfad>`, `-Folders <Namen>`, `-WhatIf`, `-Confirm`, `-EnglishOutput`. Löscht lokale Dateien mit übereinstimmendem SHA-256-Hash und leere Unterordner, wenn der entsprechende Nextcloud-Ordner existiert. |

Details und Beispiele stehen in der [Nextcloud-Anleitung](nextcloud/README.de.md).

## Offene Punkte

Geplante Arbeiten stehen in [open-issues.md](open-issues.md) (englisch).

## Lizenz

Das Projekt steht unter der [MIT-Lizenz](LICENSE.md).
Hinweise zum Mitwirken stehen in [CONTRIBUTING.md](CONTRIBUTING.md).
