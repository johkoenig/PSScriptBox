# AGENTS.md

Vorgaben für die Arbeit an diesem Repository, insbesondere für die PowerShell-Skripte.

## Sprache und Kommentare
- Benutzerseite (Texte, Ausgaben, Fehlermeldungen) und Kommentare in Skripten auf Deutsch; technische Fachbegriffe und Tesseract-Sprachcodes (z. B. `deu`, `eng`) auf Englisch.
- Jedes Skript beginnt mit comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, mindestens ein `.EXAMPLE`, `.NOTES` mit Abhängigkeiten).
- Jede Funktion dokumentiert Zweck, Parameter und Rückgabewerte (Kommentarblock oder comment-based help).
- Nicht offensichtliche Entscheidungen kommentieren (das Warum), z. B. warum ein externes Programm direkt über `[System.Diagnostics.Process]` gestartet wird.
- Keine selbsterklärenden Kommentare; stattdessen Abschnitte im Hauptteil mit kurzen Überschriften strukturieren.

## PowerShell-Stil
- Am Skriptanfang `Set-StrictMode -Version Latest` und `$ErrorActionPreference = 'Stop'` setzen.
- `[CmdletBinding()]` an Skript und Funktionen; Pflichtparameter mit `[Parameter(Mandatory)]` kennzeichnen.
- Benutzerfeedback über `Write-Host` / `Write-Warning` / `Write-Error`, nicht über `Write-Output`.
- Dateipfade konsequent mit `-LiteralPath` und `Join-Path` behandeln; Benutzereingaben vor Verwendung mit `Trim()` und `ExpandEnvironmentVariables` normalisieren.
- Externe Konsolenprogramme mit umgeleiteten Streams starten und asynchron lesen, damit deren Fehler nicht als PowerShell-Terminierungsfehler fehlinterpretiert werden und große Ausgaben die Pipe nicht blockieren.

## Abhängigkeiten und Installation
- Skripte installieren keine Software und benötigen keine Administratorrechte.
- Fehlende Abhängigkeiten werden gesammelt geprüft und am Stück mit Installationshinweisen gemeldet.
- Optionale Werkzeuge (z. B. `pngquant`) dürfen den Lauf nicht blockieren und werden nicht als Pflicht behandelt. `jbig2` wird nicht verwendet.

## Umgang mit Dateien und Daten
- **Originale bleiben unverändert:** Eingabedateien werden nie überschrieben. Das verarbeitete Ergebnis wird als neue Datei mit dem Suffix `_ocr` neben das Original gelegt.
- Ein Lauf gilt nur dann als fehlgeschlagen, wenn OCRmyPDF tatsächlich fehlschlägt oder das Ergebnis hash-gleich (SHA-256) zum Original ist, d. h. keine Veränderung stattgefunden hat. Ein größeres, aber inhaltlich verändertes Ergebnis ist ein Erfolg.
- Temporäre Dateien landen neben der Eingabedatei und werden im `finally`-Block zuverlässig entfernt.
- Keine Geheimnisse, Tokens, API-Schlüssel oder persönlichen Daten im Repository.

## Projektkonventionen (choco/pdf-toolbox.ps1)
- Standard-Sprachfolge für die OCR: `deu+eng+fra+ita+spa` (Deutsch, Englisch, Französisch, Italienisch, Spanisch, in dieser Reihenfolge). Eine abweichende Sprachfolge kann per Parameter oder interaktiv vorgegeben werden; die Reihenfolge der Eingabe bestimmt die Priorität.
- **Begradigung von Scan-Seiten ist standardmäßig aktiv (`--deskew`).** Verdrehte Seiten werden automatisch um 90°, 180° oder 270° korrigiert (**`--rotate-pages`** ist standardmäßig **deaktiviert**).
- Quelle für Tesseract-Sprachdaten ist https://github.com/tesseract-ocr/tessdata . Sind angeforderte Sprachen lokal nicht installiert, gibt das Skript einen Zweizeiler aus: Aufforderung, den Download-Befehl in einer Admin-Shell auszuführen (lädt alle Sprachen herunter), gefolgt vom Befehl.
- Die JPEG-Kompression für Scan-Bilder ist standardmäßig auf Qualität 75 eingestellt (`--pdfa-image-compression jpeg --jpeg-quality 75`), zusätzlich wird die Auflösung der eingebetteten Bilder auf **300 DPI** begrenzt (`--image-dpi 300`, Parameter `-ImageDpi`).

## Qualitätssicherung vor dem Commit
- Skriptänderungen mindestens mit einem Beispiel-PDF testen (Parametermodus und interaktiver Modus), soweit in der Umgebung möglich.
- Vor dem Commit `git diff` prüfen; keine lokalen Test-PDFs, temporären Dateien oder Binärdateien einchecken.
- Commit-Messages kurz und sachlich halten.
