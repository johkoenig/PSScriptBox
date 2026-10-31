# PSScriptBox

> Englische Version: [README.md](README.md)

> [!CAUTION]
> 🔴 **ALPHA: Diese Skripte NICHT auf produktiven Daten ausführen.** Nur mit Kopien der Dateien testen und Sicherungen
anlegen.

PSScriptBox ist eine Sammlung von PowerShell-Werkzeugen für die Verarbeitung von PDFs und Medien, die Git-Konfiguration
und lokale Nextcloud-Abläufe.

## PDF-Werkzeuge

Diese Skripte machen PDFs durchsuchbar, verkleinern Dateien, finden fehlende Textebenen und verwalten Sicherungen.
Einrichtung, Beispiele und Sicherheitshinweise stehen in der [PDF-Anleitung](pdf/README.de.md).

| Skript                          | Zweck                                                                   |
|---------------------------------|-------------------------------------------------------------------------|
| `ConvertTo-SearchablePdf.ps1`   | OCR zu gescannten PDFs hinzufügen und Seitenrotation korrigieren.       |
| `Optimize-PdfSize.ps1`          | PDF-Dateien durch Verkleinern der Bilder reduzieren.                    |
| `Find-PdfsWithoutTextLayer.ps1` | PDFs mit fehlenden oder unvollständigen Textebenen finden.              |
| `Remove-PdfBackups.ps1`         | `_orig`-Sicherungen entfernen, wenn eine bearbeitete PDF vorhanden ist. |
| `Restore-PdfOriginals.ps1`      | PDFs aus passenden `_orig`-Sicherungen wiederherstellen.                |

## Medienwerkzeuge

Medien lassen sich verkleinern, mit wiederhergestellten Datumsangaben versehen und von Sicherungen oder Live Photos
bereinigen. Abhängigkeiten, Beispiele und Details stehen in der [Anleitung zu den Medienwerkzeugen](media/README.de.md).

| Skript                    | Zweck                                                                           |
|---------------------------|---------------------------------------------------------------------------------|
| `Optimize-MediaSize.ps1`  | Unterstützte Videos und JPEG-Fotos nach Größe und Dichte optimieren.            |
| `Remove-MediaBackups.ps1` | `_orig`-Sicherungen entfernen, wenn eine bearbeitete Datei vorhanden ist.       |
| `Remove-LivePhotos.ps1`   | MOV-Videos entfernen, wenn ein gleichnamiges JPG-Foto vorhanden ist.            |
| `Restore-MediaDate.ps1`   | Mediendaten wiederherstellen und Dateien nach dem ermittelten Datum umbenennen. |

## Git-Werkzeuge

Git-Identität und empfohlene Einstellungen konfigurieren oder veraltete lokale Branches bereinigen. Beispiele und
Details stehen in der [Git-Anleitung](git/README.de.md).

| Skript                            | Zweck                                                                                             |
|-----------------------------------|---------------------------------------------------------------------------------------------------|
| `Initialize-GitConfiguration.ps1` | Lokale oder globale Git-Identität festlegen und empfohlene Einstellungen konfigurieren.           |
| `Remove-ObsoleteGitBranches.ps1`  | Veraltete lokale Branches finden und entfernen; `main` und der aktuelle Branch bleiben geschützt. |

## Nextcloud

Ausgewählte Windows-Benutzerordner in vorhandene Nextcloud-Ordner kopieren und lokale Kopien nach abgeschlossener
Synchronisierung optional bereinigen. Details stehen in
der [Anleitung zu den Nextcloud-Werkzeugen](nextcloud/README.de.md).

| Skript | Zweck |
| --- | --- |
| `Copy-UserDataToNextcloud.ps1` | Ausgewählte Ordner kopieren, ohne Quelldateien zu löschen. |
| `Remove-MigratedUserData.ps1` | Lokale Dateien entfernen, deren Nextcloud-Kopien verifiziert wurden. |

## Tests

Die Testsuite lässt sich im Repository-Stamm mit `.\tests\Invoke-Tests.ps1` starten; erforderlich ist Pester 5 oder
höher. Mit `-Coverage` werden die Zeilenabdeckung interner Hilfsfunktionen, nicht abgedeckte Zeilenbereiche und eine
Zusammenfassung ausgegeben. Vollständig abgedeckte Dateien erscheinen nicht in der Dateiliste. GitHub Actions führt
die Tests außerdem unter Windows PowerShell 5.1 und PowerShell 7 aus.

## Mitwirken

Die Schritte für Beiträge stehen in [CONTRIBUTING.md](CONTRIBUTING.md); [AGENTS.md](AGENTS.md) enthält die Entwicklungs-
und Dokumentationsregeln des Repositorys.

## Lizenz

PSScriptBox steht unter der [MIT-Lizenz](LICENSE.md).
