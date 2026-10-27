> Englische Version: [README.md](README.md)

Dieser Ordner enthält PowerShell-Werkzeuge zur Verkleinerung von Videodateien unter Erhalt der Datumsangaben. Verwende
Windows PowerShell 5.1 oder PowerShell 7 in einer normalen Benutzersitzung.

## Schnellstart

1. Installiere FFmpeg mit dem `libx265`-Encoder und ExifTool und stelle beide Programme über `PATH` bereit.
2. Zeige eine Vorschau der MOV- und MP4-Dateien in einem Ordner an:

   ```powershell
   .\Optimize-MediaSize.ps1 -InputPath 'C:\Videos' -WhatIf
   ```

3. Optimiere den Ordner und behalte jedes Original als `_orig`-Sicherung mit der ursprünglichen Erweiterung:

   ```powershell
   .\Optimize-MediaSize.ps1 -InputPath 'C:\Videos'
   ```

Die PowerShell-Ausführungsrichtlinie kann eine richtlinienkonforme Methode erfordern, um lokale Skripte auszuführen.
Schwäche die systemweite Richtlinie nicht nur für diese Werkzeuge.

## Abhängigkeiten

`Optimize-MediaSize.ps1` benötigt:

- FFmpeg mit dem `libx265`-Encoder.
- FFprobe zur Erkennung des Video-Codecs; es ist in FFmpeg enthalten.
- ExifTool zum Kopieren der Metadaten und Prüfen eingebetteter Datums- und Zeitangaben.

Wenn Chocolatey installiert ist, lassen sich beide Programme mit diesem Befehl installieren:

```powershell
choco install ffmpeg exiftool -y
```

FFmpeg muss `libx265` enthalten. Beide Programme müssen über `PATH` auffindbar sein. Das Skript prüft nur ihre
Verfügbarkeit; es installiert keine Software und benötigt keine Administratorrechte.

## Skripte und Schalter

### `Optimize-MediaSize.ps1`

Kodiert geeignete `.mov`- und `.mp4`-Dateien als 720p-H.265/HEVC-MP4 mit dem `libx265`-Encoder, einer durchschnittlichen
Video-Bitrate von 1,9 Mb/s, dem Preset `medium` und 96 kb/s Audio. Querformat wird auf 1280x720 begrenzt, Hochformat auf
720x1280. Für ein sechsminütiges Video ergibt das ungefähr 90 MB; die tatsächliche Größe hängt von Dauer und Inhalt ab.
H.264-Dateien bis einschließlich 1,9 Mb/s sowie HEVC-, AV1- und VP9-Dateien werden übersprungen. H.264 mit unbekannter
Bitrate wird vorsichtshalber übersprungen; eine passende `_orig`-Sicherung verhindert wiederholte
verlustbehaftete Kodierung. Andere Codecs werden neu kodiert. Ordner werden rekursiv durchsucht; ein Ergebnis wird nur
übernommen, wenn es kleiner als die Quelldatei ist.

| Parameter / Schalter | Beschreibung                                                                                                  |
|----------------------|---------------------------------------------------------------------------------------------------------------|
| `-InputPath <Pfad>`  | MOV- oder MP4-Datei oder zu verarbeitender Ordner. Ohne Angabe wird nach dem Pfad gefragt.                    |
| `-ReplaceOriginal`   | Ersetzt die Quelldatei nach erfolgreicher Kodierung und Datumsprüfung, ohne eine `_orig`-Sicherung anzulegen. |
| `-WhatIf`            | Prüft Codecs und zeigt geplante Änderungen an, ohne zu kodieren oder Dateien zu ändern.                       |
| `-Confirm`           | Fragt vor der Verarbeitung jedes geeigneten Videos nach.                                                      |
| `-EnglishOutput`     | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache.                                 |

Beispiele:

```powershell
.\Optimize-MediaSize.ps1
.\Optimize-MediaSize.ps1 -InputPath 'C:\Videos' -WhatIf
.\Optimize-MediaSize.ps1 -InputPath 'C:\Videos\clip.mp4'
.\Optimize-MediaSize.ps1 -InputPath 'C:\Videos' -ReplaceOriginal -Confirm
```

Standardmäßig wird das Original erst dann nach `<Name>_orig.mov` oder `<Name>_orig.mp4` verschoben, wenn eine kleinere
MP4-Datei mit geprüften Datumsangaben bereitsteht. Eine vorhandene Ausgabe oder Sicherung wird niemals überschrieben;
die Datei wird als Problem gemeldet. Bei der Optimierung einer MP4-Datei wird die Ausgabe erst an deren ursprünglichem
Pfad abgelegt, nachdem das Original in die Sicherung verschoben wurde.

## Gemeinsame PowerShell-Parameter

Das Skript unterstützt allgemeine Parameter wie `-Verbose`, `-Debug`, `-ErrorAction`, `-WarningAction`, `-WhatIf` und
`-Confirm`. `-WhatIf` und `-Confirm` werden über `SupportsShouldProcess` bereitgestellt.

## Sicherheit und Verhalten

- FFmpeg übernimmt globale und Stream-Metadaten sowie Kapitel. ExifTool kopiert unterstützte Metadaten aus der
  Quelldatei. Vor der Übernahme vergleicht das Skript Datei-, EXIF-/XMP- und Container-Aufnahmedaten. Erstellungs- und
  Änderungszeiten
  einzelner Tracks werden nicht verglichen, da sich die Ausgabestreams unterscheiden können. Wenn relevante
  Datumsmetadaten nicht kopiert werden können oder abweichen, bleibt die Quelldatei erhalten.
- Erstellungszeit, Änderungszeit und letzter Zugriff der Quelldatei werden auf der MP4-Datei wiederhergestellt.
  Unterstützte EXIF-/XMP- und Container-Aufnahmedaten werden kopiert und geprüft. Windows erlaubt dem Skript nicht, die
  NTFS-
  Änderungszeit festzulegen; dieser niedrigstufige Dateisystem-Zeitstempel kann daher nicht erhalten werden.
- Das Original wird nur ersetzt, wenn die MP4-Datei kleiner ist. Vorhandene Ausgaben und Sicherungen bleiben erhalten
  und werden nicht überschrieben.
- H.264-Dateien mit hoher Bitrate und passender vorhandener `_orig`-Sicherung werden übersprungen, um bei späteren
  Durchläufen eine weitere verlustbehaftete Kodierung zu vermeiden.
- Die H.265-Kodierung mit durchschnittlicher Bitrate ist verlustbehaftet und kann keine unveränderte wahrnehmbare
  Qualität garantieren. Die Bitrate zielt auf einen Größenbereich, nicht auf eine feste Ausgabegröße.
- Temporäre MP4-Dateien enden auf `.mp4.part`, werden neben der Quelldatei erstellt und nach der Verarbeitung entfernt.
- `-ReplaceOriginal` ersetzt die Quelldatei erst, wenn die Ausgabe vorhanden, kleiner und ihre Datumsangaben geprüft
  sind. Sichere wichtige Dateien vor Verwendung dieses Schalters.
- Das Skript löscht keine zugehörigen Live-Photo-Videos und verarbeitet keine anderen Formate als `.mov` und `.mp4`.
- Verwende das Werkzeug nicht für Dateien, die byte-identisch bleiben müssen.
- Das Projekt steht unter der [MIT-Lizenz](../LICENSE.md).
- Hinweise zum Mitwirken stehen in [CONTRIBUTING.md](../CONTRIBUTING.md).
