# PDF-PowerShell-Werkzeuge

> Englische Version: [README.md](README.md)

Dieser Ordner enthält PowerShell-Werkzeuge zum Einrichten und Verarbeiten von PDF-Dateien. Verwende Windows PowerShell 5.1 oder PowerShell 7 und starte die Skripte in einer normalen Benutzersitzung, sofern ein Skript nicht ausdrücklich Administratorrechte anfordert.

## Schnellstart

1. Öffne PowerShell in diesem Ordner.
2. Starte das gewünschte PDF-Skript. Skripte mit externen Werkzeugen prüfen
   diese und geben bei fehlenden Programmen Installationshinweise aus.
3. Beachte Hinweise zu fehlenden Tesseract-Sprachdaten; Skripte laden keine
   `.traineddata`-Dateien herunter.
4. Führe OCR für Scans und Größenreduzierung als getrennte Schritte aus:

   ```powershell
   .\ConvertTo-SearchablePdf.ps1 -InputPath 'C:\PDFs'
   .\Optimize-PdfSize.ps1 -InputPath 'C:\PDFs'
   ```

Die PowerShell-Ausführungsrichtlinie kann eine genehmigte Vorgehensweise zum Ausführen lokaler Skripte erfordern. Ändere die systemweite Richtlinie nicht allein für diese Werkzeuge.

## Abhängigkeiten einrichten

PDF-Skripte mit externen Programmen prüfen ihre erforderlichen Programme und
Python-Module vor der Verarbeitung. Fehlende Abhängigkeiten werden einzeln mit
Chocolatey-Befehlen, direkten Download-Links oder einem pip-Befehl für den
ausgewählten Python-Interpreter gemeldet. Die Skripte installieren keine
Abhängigkeiten und fordern keine Administratorrechte an. Tesseract-Sprachdaten
werden nicht heruntergeladen: Standard sind `deu+eng+fra+ita+spa`; `deu` und
`eng` sind erforderlich, die übrigen Sprachen optional. Die Sicherungs- und
Wiederherstellungsskripte nutzen integrierte PowerShell-Funktionen und benötigen
keine zusätzliche Software.

## Skripte und Schalter

### `ConvertTo-SearchablePdf.ps1`

Fügt gescannten PDFs OCR hinzu und korrigiert Schräglagen und verdrehte Seiten. Digital erzeugte PDFs werden anhand
sichtbaren Texts und vorhandener Bildressourcen heuristisch erkannt und übersprungen; gemischte oder ungewöhnliche
Dokumente können falsch eingeordnet werden. Verschlüsselte und digital signierte PDFs können nicht verarbeitet werden
und werden als Probleme gemeldet. Die Bildoptimierung von OCRmyPDF ist deaktiviert, damit Herunterskalieren und
JPEG-Komprimierung ausschließlich im separaten Skript `Optimize-PdfSize.ps1` stattfinden. Vorhandene OCR-Textebenen
bleiben erhalten; Ghostscript rendert temporäre
Seitenvorschauen für die Tesseract-Ausrichtungserkennung, und pikepdf aktualisiert nur die Seitenrotations-Metadaten.
Dadurch wird OCR nicht erneut ausgeführt und Seiten mit Textebene werden nicht gerastert. Bei teilweise erkannten Scans
wird OCR nur auf Seiten ohne Text ergänzt; die Schräglagenkorrektur wirkt nur auf diese Seiten. Ghostscript ist für
normale OCR optional, wird jedoch zur Rotationserkennung auf Seiten mit vorhandener Textebene benötigt. Nach
erfolgreicher Verarbeitung wird die Eingabedatei ersetzt; standardmäßig wird vorher eine Sicherung `<Name>_orig.pdf`
erstellt. Existiert diese Sicherung bereits, bleibt sie erhalten und die Eingabedatei wird direkt ersetzt.

| Parameter / Schalter | Beschreibung                                                                                                                                                       |
|----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `-InputPath <Pfad>`  | PDF-Datei oder Ordner. Ohne Angabe wird der Pfad abgefragt.                                                                                                        |
| `-Language <Codes>`  | Tesseract-Sprachen, getrennt durch `+`. Standard: `deu+eng+fra+ita+spa`; `deu` und `eng` sind erforderlich; nicht installierte optionale Sprachen werden entfernt. |
| `-NoDeskew`          | Deaktiviert die Schräglagenkorrektur auf Seiten, die OCR benötigen. Seiten mit vorhandenem Text werden nicht begradigt.                                            |
| `-NoRotationOfPages` | Deaktiviert die automatische Erkennung und Korrektur verdrehter Seiten. Standardmäßig aktiv, Konfidenzschwelle `5`.                                                |
| `-ReplaceOriginal`   | Ersetzt die Eingabe, ohne eine neue `_orig`-Sicherung anzulegen.                                                                                                   |
| `-EnglishOutput`     | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache.                                                                                      |

Beispiele:

```powershell
.\ConvertTo-SearchablePdf.ps1
.\ConvertTo-SearchablePdf.ps1 -InputPath 'C:\PDFs' -NoRotationOfPages
.\ConvertTo-SearchablePdf.ps1 -InputPath 'C:\PDFs\Scan.pdf' -ReplaceOriginal
.\ConvertTo-SearchablePdf.ps1 -InputPath 'C:\PDFs' -Language 'deu+eng' -EnglishOutput
```

Das Ergebnis ist eine normale PDF und kein PDF/A. Vorhandene OCR-Textebenen werden bei späteren Läufen nicht erneuert;
Seitenrotationen werden nur geändert, wenn die Ausrichtungserkennung eine Korrektur oberhalb der Konfidenzschwelle
feststellt. Regulär übersprungene und unveränderte Dateien werden in der Zusammenfassung gezählt, aber nicht einzeln
aufgeführt; verschlüsselte oder signierte PDFs erscheinen in der Problemliste.

### `Optimize-PdfSize.ps1`

Verkleinert PDFs, indem Ghostscript Farb-, Graustufen- und Schwarzweißbilder herunterskaliert. Farb- und
Graustufenbilder werden als JPEG kodiert. PDFs unter 1 MB werden standardmäßig übersprungen; Ziel sind 300 DPI und
JPEG-Qualität 75. Digital signierte und verschlüsselte PDFs können nicht verarbeitet werden und werden als Probleme
gemeldet. Digital erzeugte PDFs werden ebenfalls verarbeitet. Das Original wird nur ersetzt, wenn das optimierte PDF
kleiner ist; standardmäßig wird eine `_orig.pdf`-Sicherung angelegt und vorhandene Sicherungen bleiben erhalten.
Dateien unterhalb der Mindestgröße und Dateien ohne Größenreduzierung werden als übersprungen gezählt, aber in der
Zusammenfassung nicht einzeln aufgeführt. Bei Ordnern werden zuerst alle PDFs ermittelt; verarbeitet werden nur
Dateien, die mindestens die Mindestgröße erreichen.

| Parameter / Schalter   | Beschreibung                                                                                                                         |
|------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| `-InputPath <Pfad>`    | PDF-Datei oder Ordner. Ohne Angabe wird der Pfad abgefragt.                                                                          |
| `-Dpi <50-1200>`       | Zielauflösung für das Herunterskalieren der Bilder. Standard: `300`.                                                                 |
| `-JpegQuality <1-100>` | JPEG-Qualität für heruntergerechnete Farb- und Graustufenbilder. Standard: `75`.                                                     |
| `-MinFileSize <Bytes>` | Mindestgröße des Originals zur Verarbeitung. Standard: `1MB`; mit `0` deaktiviert. PowerShell-Größenangaben wie `2MB` sind zulässig. |
| `-ReplaceOriginal`     | Ersetzt die Eingabe, ohne eine neue `_orig`-Sicherung anzulegen.                                                                     |
| `-EnglishOutput`       | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache.                                                        |

Beispiele:

```powershell
.\Optimize-PdfSize.ps1
.\Optimize-PdfSize.ps1 -InputPath 'C:\PDFs' -Dpi 200 -JpegQuality 65 -MinFileSize 2MB
.\Optimize-PdfSize.ps1 -InputPath 'C:\PDFs\Document.pdf' -ReplaceOriginal
```

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

### `Remove-PdfBackups.ps1`

Findet `_orig.pdf`-Sicherungen, zu denen die bearbeitete PDF im selben Ordner vorhanden ist. Jede Löschung unterliegt dem Bestätigungsverhalten von PowerShell.

| Parameter / Schalter  | Beschreibung                                                                               |
|-----------------------|--------------------------------------------------------------------------------------------|
| `-InputPath <Ordner>` | Rekursiv zu durchsuchender Ordner. Ohne Angabe wird der Pfad abgefragt.                    |
| `-WhatIf`             | Zeigt geplante Löschungen an, ohne Dateien zu löschen.                                     |
| `-Confirm`            | Fragt vor jeder Löschung nach. Ohne diesen Schalter erfolgt standardmäßig keine Rückfrage. |
| `-EnglishOutput`      | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache.              |

Beispiele:

```powershell
.\Remove-PdfBackups.ps1 -InputPath 'C:\PDFs' -WhatIf
.\Remove-PdfBackups.ps1 -InputPath 'C:\PDFs'
.\Remove-PdfBackups.ps1 -InputPath 'C:\PDFs' -Confirm
.\Remove-PdfBackups.ps1 -InputPath 'C:\PDFs' -EnglishOutput
```

### `Restore-PdfOriginals.ps1`

Findet `_orig.pdf`-Sicherungen, zu denen die bearbeitete PDF im selben Ordner vorhanden ist. Für jedes bestätigte Paar
wird die bearbeitete PDF atomar durch das Original ersetzt; die bearbeitete Datei wird dadurch
entfernt und die `_orig`-Sicherung aufgebraucht. Standardmäßig erfolgt keine Rückfrage; mit `-Confirm` lassen sich
Rückfragen pro Datei aktivieren.

| Parameter / Schalter  | Beschreibung                                                                                        |
|-----------------------|-----------------------------------------------------------------------------------------------------|
| `-InputPath <Ordner>` | Rekursiv zu durchsuchender Ordner. Ohne Angabe wird der Pfad abgefragt.                             |
| `-WhatIf`             | Zeigt geplante Wiederherstellungen an, ohne Dateien zu ändern.                                      |
| `-Confirm`            | Fragt vor jeder Wiederherstellung nach. Ohne diesen Schalter erfolgt standardmäßig keine Rückfrage. |
| `-EnglishOutput`      | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache.                       |

Beispiele:

```powershell
.\Restore-PdfOriginals.ps1 -InputPath 'C:\PDFs' -WhatIf
.\Restore-PdfOriginals.ps1 -InputPath 'C:\PDFs'
.\Restore-PdfOriginals.ps1 -InputPath 'C:\PDFs' -Confirm -EnglishOutput
```

## Gemeinsame PowerShell-Parameter

Skripte unterstützen, soweit anwendbar, außerdem PowerShell-Standardparameter wie `-Verbose`, `-Debug`, `-ErrorAction`
und `-WarningAction`. `Remove-PdfBackups.ps1` und `Restore-PdfOriginals.ps1` unterstützen über
`SupportsShouldProcess` auch `-WhatIf` und `-Confirm`.

## Sicherheit und Verhalten

- Beide Optimierungsskripte legen temporäre Dateien neben der Eingabe an und entfernen sie nach der Verarbeitung.
- Neben der PDF werden keine dauerhaften Status- oder Markierungsdateien angelegt. Temporäre Verarbeitungsdateien werden nach dem Lauf entfernt.
- Die OCR-Klassifizierung verwendet zustandslos sichtbaren Text und Hinweise auf gescannte Bildseiten. Sie ist eine
  bestmögliche Heuristik; gemischte oder ungewöhnliche PDFs können falsch eingeordnet werden. Vorhandene OCR-Textebenen
  bleiben erhalten; Seitenrotationen werden durch Aktualisieren der PDF-Seitenmetadaten korrigiert, und OCR wird nur
  für Seiten ohne Textebene ergänzt.
- Das OCR-Skript akzeptiert geänderte Ergebnisse auch dann, wenn sie größer als das Original sind. Das
  Größenoptimierungsskript ersetzt eine PDF nur, wenn Ghostscript ein kleineres Ergebnis erzeugt.
- Vorhandene `_orig`-Sicherungen bleiben erhalten.
- `Remove-PdfBackups.ps1` löscht nur Sicherungen, zu denen die bearbeitete PDF vorhanden ist.
- `Restore-PdfOriginals.ps1` stellt nur passende Sicherungs-/Bearbeitungspaare wieder her; dabei ersetzt das Original
  die
  bearbeitete PDF und die `_orig`-Sicherung wird entfernt.
- Verwende diese Werkzeuge nicht für Dateien, die byte-identisch bleiben müssen, etwa digital signierte PDFs.
- Das Projekt steht unter der [MIT-Lizenz](../LICENSE.md).
- Hinweise zum Mitwirken stehen in [CONTRIBUTING.md](../CONTRIBUTING.md).
