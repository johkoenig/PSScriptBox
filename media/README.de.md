> Englische Version: [README.md](README.md)

Dieser Ordner enthält PowerShell-Werkzeuge zur Verkleinerung von Videos und hochauflösenden JPEG-Fotos unter Erhalt der
Datumsangaben. Verwende Windows PowerShell 5.1 oder PowerShell 7 in einer normalen Benutzersitzung.

## Schnellstart

1. Installiere FFmpeg mit den `libx265`- und MJPEG-Encodern sowie ExifTool und stelle alle Programme
   über `PATH` bereit.
2. Zeige eine Vorschau der Video- und JPEG-Dateien in einem Ordner an:

   ```powershell
   .\Optimize-MediaSize.ps1 -InputPath 'C:\Medien' -WhatIf
   ```

3. Optimiere den Ordner und behalte jedes Original als `_orig`-Sicherung mit der ursprünglichen Erweiterung:

   ```powershell
   .\Optimize-MediaSize.ps1 -InputPath 'C:\Medien'
   ```

4. Zeige eine Vorschau der Sicherungen an, deren bearbeitete Mediendatei vorhanden ist:

   ```powershell
   .\Remove-MediaBackups.ps1 -InputPath 'C:\Medien' -WhatIf
   ```

5. Lösche nach Prüfung der Liste geeignete Sicherungen; das Skript fragt vor jeder Löschung nach:

   ```powershell
   .\Remove-MediaBackups.ps1 -InputPath 'C:\Medien'
   ```

Die PowerShell-Ausführungsrichtlinie kann eine richtlinienkonforme Methode erfordern, um lokale Skripte auszuführen.
Schwäche die systemweite Richtlinie nicht nur für diese Werkzeuge.

## Abhängigkeiten

`Optimize-MediaSize.ps1` benötigt:

- FFmpeg mit den `libx265`- und MJPEG-Encodern.
- FFprobe zum Erkennen von Video-Codecs und Auslesen der JPEG-Abmessungen; es ist in FFmpeg enthalten.
- ExifTool zum Kopieren der Metadaten und Prüfen von Datei-, EXIF-/XMP- und Container-Aufnahmedaten.

Wenn Chocolatey installiert ist, lassen sich beide Programme mit diesem Befehl installieren:

```powershell
choco install ffmpeg exiftool -y
```

FFmpeg muss `libx265` und MJPEG enthalten. Alle Programme müssen über `PATH` auffindbar sein. Das Skript prüft nur ihre
Verfügbarkeit; es installiert keine Software und benötigt keine Administratorrechte.

## Skripte und Schalter

### `Optimize-MediaSize.ps1`

Kodiert geeignete `.mov`- und `.mp4`-Dateien als 720p-H.265/HEVC-MP4 mit dem `libx265`-Encoder, einer durchschnittlichen
Video-Bitrate von 1,9 Mb/s, dem Preset `medium` und 96 kb/s Audio. Querformat wird auf 1280x720 begrenzt, Hochformat auf
720x1280. Für ein sechsminütiges Video ergibt das ungefähr 90 MB; die tatsächliche Größe hängt von Dauer und Inhalt ab.
H.264-Dateien bis einschließlich 1,9 Mb/s sowie HEVC-, AV1- und VP9-Dateien werden übersprungen. H.264 mit unbekannter
Bitrate wird vorsichtshalber übersprungen; eine passende `_orig`-Sicherung verhindert wiederholte verlustbehaftete
Kodierung. Andere Codecs werden neu kodiert.

JPEG-Fotos über 6 MB werden anhand ihrer Quelldateigröße und Pixelabmessungen verkleinert und mit der hohen
MJPEG-Qualität
von FFmpeg neu kodiert. Die geschätzte Ausgabe-Pixelzahl entspricht der Quell-Pixelzahl multipliziert mit
`5,5 MB / Quelldateigröße`; Breite und Höhe werden mit der Quadratwurzel dieses Verhältnisses skaliert. Die tatsächliche
Ausgabegröße hängt von Bilddetails und Kompression ab; 5,5 MB sind ein Schätzwert, keine feste Obergrenze. Fotos bis
einschließlich 6 MB werden übersprungen. Ordner werden rekursiv durchsucht; ein Ergebnis wird nur übernommen, wenn es
kleiner als die Quelldatei ist.

| Parameter / Schalter | Beschreibung                                                                                                    |
|----------------------|-----------------------------------------------------------------------------------------------------------------|
| `-InputPath <Pfad>`  | MOV-, MP4-, JPG- oder JPEG-Datei oder zu verarbeitender Ordner. Ohne Angabe wird nach dem Pfad gefragt.         |
| `-ReplaceOriginal`   | Ersetzt die Quelldatei nach erfolgreicher Optimierung und Datumsprüfung, ohne eine `_orig`-Sicherung anzulegen. |
| `-WhatIf`            | Prüft Codecs und zeigt geplante Änderungen an, ohne zu kodieren oder Dateien zu ändern.                         |
| `-Confirm`           | Fragt vor der Verarbeitung jedes geeigneten Videos oder Fotos nach.                                             |
| `-EnglishOutput`     | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache.                                   |

Beispiele:

```powershell
.\Optimize-MediaSize.ps1
.\Optimize-MediaSize.ps1 -InputPath 'C:\Videos' -WhatIf
.\Optimize-MediaSize.ps1 -InputPath 'C:\Videos\clip.mp4'
.\Optimize-MediaSize.ps1 -InputPath 'C:\Fotos\großes-kamerafoto.jpg'
.\Optimize-MediaSize.ps1 -InputPath 'C:\Videos' -ReplaceOriginal -Confirm
```

Standardmäßig wird das Original erst dann mit seiner ursprünglichen Erweiterung nach `<Name>_orig` verschoben, wenn ein
kleineres Ergebnis mit geprüften Datumsangaben bereitsteht. Eine vorhandene Sicherung wird niemals überschrieben; die
Datei wird als Problem gemeldet.

### `Remove-MediaBackups.ps1`

Findet rekursiv `_orig`-Sicherungen für MOV-, MP4-, JPG- und JPEG-Dateien. Eine Sicherung ist nur geeignet, wenn die
bearbeitete Datei im selben Ordner vorhanden ist. Eine MOV-Sicherung wie `clip_orig.mov` wird der optimierten Datei
`clip.mp4` zugeordnet; andere unterstützte Sicherungen werden mit derselben Erweiterung abgeglichen. `-WhatIf` zeigt
eine Vorschau an; standardmäßig fragt das Skript vor jeder Löschung nach.

| Parameter / Schalter | Beschreibung                                                                                     |
|----------------------|--------------------------------------------------------------------------------------------------|
| `-InputPath <Pfad>`  | Rekursiv zu durchsuchender Ordner. Ohne Angabe wird nach einem Ordner gefragt.                   |
| `-WhatIf`            | Zeigt geeignete Sicherungen an, ohne Dateien zu löschen.                                         |
| `-Confirm`           | Fragt vor jeder geeigneten Sicherung nach; mit `-Confirm:$false` wird die Rückfrage unterdrückt. |
| `-EnglishOutput`     | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache.                    |

Beispiele:

```powershell
.\Remove-MediaBackups.ps1
.\Remove-MediaBackups.ps1 -InputPath 'C:\Medien' -WhatIf
.\Remove-MediaBackups.ps1 -InputPath 'C:\Medien'
```

## Gemeinsame PowerShell-Parameter

Beide Skripte unterstützen allgemeine Parameter wie `-Verbose`, `-Debug`, `-ErrorAction`, `-WarningAction`, `-WhatIf`
und `-Confirm`. `-WhatIf` und `-Confirm` werden über `SupportsShouldProcess` bereitgestellt.

## Sicherheit und Verhalten

- FFmpeg übernimmt Video-Metadaten und Kapitel; ExifTool kopiert unterstützte Metadaten. Datei-, EXIF-/XMP- und
  Container-Aufnahmedaten werden vor der Übernahme geprüft. Erstellungs- und Änderungszeiten einzelner Video-Tracks
  werden nicht verglichen, da sich die Ausgabestreams unterscheiden können. Der Samsung-Maker-Note-Zeitstempel
  `TimeStamp` und das EXIF-Feld `IFD0:ModifyDate`, das kein Aufnahmedatum ist, werden ebenfalls ausgeschlossen;
  standardisierte EXIF-Aufnahmedaten werden weiterhin geprüft. Bei abweichenden relevanten Daten bleibt die Quelldatei
  erhalten.
- Erstellungszeit, Änderungszeit und letzter Zugriff der Quelldatei werden auf der optimierten Datei wiederhergestellt.
  Windows erlaubt dem Skript nicht, die NTFS-Änderungszeit festzulegen; dieser niedrigstufige Dateisystem-Zeitstempel
  kann daher nicht erhalten werden.
- JPEG-Fotos bis einschließlich 6 MB werden übersprungen. Größere Fotos werden proportional auf eine geschätzte
  Ausgabegröße von 5,5 MB verkleinert und mit hoher Qualität kodiert (FFmpeg-MJPEG-Qualitätswert 2). Die Skalierung ist
  verlustbehaftet; die tatsächliche Ausgabegröße variiert mit den Bilddetails und der Kompression.
- Die EXIF-Ausrichtung bleibt erhalten, ohne die Pixel der Quelldatei zu drehen. Die optimierte Datei behält die
  ursprüngliche Erweiterung `.jpg` oder `.jpeg`.
- Ein Original wird nur ersetzt, wenn das optimierte Ergebnis kleiner ist. Vorhandene Sicherungen bleiben erhalten und
  werden nicht überschrieben.
- H.264-Dateien mit hoher Bitrate und passender vorhandener `_orig`-Sicherung werden übersprungen, um bei späteren
  Durchläufen eine weitere verlustbehaftete Kodierung zu vermeiden.
- Video- und JPEG-Neukodierung sind verlustbehaftet und können keine unveränderte wahrnehmbare Qualität garantieren.
  Video-Bitrate und JPEG-Qualität zielen auf einen Größenbereich, nicht auf eine feste Ausgabegröße.
- Temporäre Video- und Fotodateien enden auf `.mp4.part` oder `.jpg.part`, werden neben der Quelldatei erstellt und
  nach der Verarbeitung entfernt.
- `-ReplaceOriginal` ersetzt die Quelldatei erst, wenn die Ausgabe vorhanden, kleiner und ihre Datumsangaben geprüft
  sind. Sichere wichtige Dateien vor Verwendung dieses Schalters.
- Das Skript löscht keine zugehörigen Live-Photo-Videos und verarbeitet keine anderen Formate als `.mov`, `.mp4`,
  `.jpg` und `.jpeg`.
- `Remove-MediaBackups.ps1` löscht nur `_orig`-Sicherungen, wenn die bearbeitete Datei im selben Ordner vorhanden ist.
  MOV-Sicherungen werden MP4-Ausgaben zugeordnet. Mit `-WhatIf` lassen sich die Kandidaten vor dem Löschen prüfen.
- Verwende das Werkzeug nicht für Dateien, die byte-identisch bleiben müssen.
- Das Projekt steht unter der [MIT-Lizenz](../LICENSE.md).
- Hinweise zum Mitwirken stehen in [CONTRIBUTING.md](../CONTRIBUTING.md).
