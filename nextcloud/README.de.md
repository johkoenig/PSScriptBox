# Nextcloud-Dateikopie und lokale Bereinigung

> Englische Version: [README.md](README.md)

Dieser Ordner enthält zwei PowerShell-Skripte: Das eine kopiert ausgewählte Windows-Benutzerordner in einen vorhandenen Nextcloud-Synchronisierungsordner, das andere entfernt die lokalen Kopien nach abgeschlossener Synchronisierung. Verwende Windows PowerShell 5.1 oder neuer in einer normalen Benutzersitzung. Administratorrechte und Drittanbieter-Module sind nicht erforderlich.

## Schnellstart

1. Öffne PowerShell in diesem Ordner.
2. Prüfe den Kopiervorgang vorab:

   ```powershell
   .\Copy-UserDataToNextcloud.ps1 -WhatIf
   ```

3. Starte die Kopie, zum Beispiel nach `D:\Nextcloud`:

   ```powershell
   .\Copy-UserDataToNextcloud.ps1 -NextcloudPath 'D:\Nextcloud'
   ```

4. Aktiviere den Nextcloud-Synchronisierungsclient wieder und warte, bis die Synchronisierung vollständig abgeschlossen ist.
5. Prüfe die lokale Bereinigung vorab und führe sie nach Durchsicht der Ausgabe ohne `-WhatIf` aus:

   ```powershell
   .\Remove-MigratedUserData.ps1 -NextcloudPath 'D:\Nextcloud' -WhatIf
   ```

## Abhängigkeiten einrichten

Der Nextcloud-Synchronisierungsclient muss installiert und eingerichtet sein. Der Synchronisierungsordner ist
standardmäßig `%USERPROFILE%\Nextcloud` oder der mit `-NextcloudPath` angegebene Pfad. Der Nextcloud-Stammordner und
jeder ausgewählte Zielordner müssen bereits existieren; benötigte Unterordner werden angelegt. Zum Kopieren werden die
integrierten PowerShell- und .NET-APIs verwendet; ein externes Kopierprogramm ist nicht erforderlich.

## Skripte und Schalter

### `Copy-UserDataToNextcloud.ps1`

Kopiert die ausgewählten Benutzerordner (Desktop, Documents, Pictures, Music, Videos) in passende Zielordner unterhalb des Nextcloud-Ordners. `Pictures` wird dem Ordner `Photos` zugeordnet. Das Skript verschiebt oder löscht niemals Quelldaten und spiegelt oder bereinigt keine Zielinhalte.

Die Skripte ermitteln die tatsächlichen Windows-Spezialordner des aktuellen Benutzers, auch wenn diese umgeleitet sind.

Das Kopierskript prüft nur Leseberechtigungen. Dateien, deren SHA-256-Hash bereits irgendwo im jeweiligen
Nextcloud-Zielordner vorkommt, werden ohne Einzelwarnung übersprungen. Die Inventarisierung berücksichtigt
Nextcloud-Platzhalter und durchläuft keine symbolischen Links oder Junctions; für den Hash-Vergleich werden Platzhalter
bei Bedarf vom Server geladen. Die übrigen Dateien werden in Blöcken mit Wiederholungsversuchen kopiert; während der
Übertragung wird ein Fortschrittsbalken angezeigt. Jede Datei wird zunächst in eine `.part`-Datei im selben Ordner
kopiert. Quell- und Zwischendatei werden per Hash geprüft, bevor die fertige Datei verschoben oder atomar ersetzt wird.

| Parameter / Schalter    | Beschreibung                                                                                                                                        |
|-------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|
| `-NextcloudPath <Pfad>` | Vorhandener Synchronisierungsordner. Ohne Angabe wird `%USERPROFILE%\Nextcloud` verwendet, falls vorhanden; andernfalls erscheint eine Pfadabfrage. |
| `-Folders <Namen>`      | Auswahl aus `Desktop`, `Documents`, `Pictures`, `Music` und `Videos`. Standardmäßig alle fünf.                                                      |
| `-WhatIf`               | Zeigt geplante Kopieraktionen an, ohne Dateien zu ändern.                                                                                           |
| `-Confirm`              | Fragt vor dem Kopieren jedes ausgewählten Ordners nach. Die erforderliche Bestätigung der pausierten Synchronisierung bleibt interaktiv.            |
| `-EnglishOutput`        | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache.                                                                       |

Beispiele:

```powershell
.\Copy-UserDataToNextcloud.ps1 -WhatIf
.\Copy-UserDataToNextcloud.ps1 -NextcloudPath 'D:\Nextcloud' -Folders Documents,Pictures
```

### `Remove-MigratedUserData.ps1`

Entfernt lokale Dateien, deren SHA-256-Hash mit dem einer Datei im zugeordneten Nextcloud-Zielordner übereinstimmt, und
löscht leere lokale Unterordner, wenn der entsprechende Nextcloud-Unterordner existiert. Das Skript fragt zuerst nach
der abgeschlossenen Synchronisierung und zeigt für jeden Hauptordner die Anzahl und Gesamtgröße der passenden Dateien
sowie die Anzahl der entsprechenden Unterordner. Standardmäßig erfolgt keine Bestätigung pro Ordner; mit `-Confirm`
lassen sich diese Rückfragen aktivieren.

Die Bestätigung der Synchronisierung ist eine Nutzeraussage; das Löschskript kann den Serverzustand nicht selbst prüfen. Vor jeder einzelnen Dateilöschung vergleicht es den lokalen Hash erneut mit allen zuvor gefundenen passenden Zieldateien. Geänderte, fehlende oder nicht mehr inhaltsgleiche Dateien bleiben lokal erhalten. Gelöscht werden nur passende lokale Dateien und leere Unterordner, für die ein gleichnamiger Nextcloud-Unterordner existiert. Die ausgewählten Hauptordner, nicht passende Dateien und ausgeschlossene Systemartefakte bleiben bestehen. Symbolische Links und Junctions werden nicht durchlaufen. Nextcloud-Platzhalter (virtuelle Dateien) werden berücksichtigt; für den Hash-Vergleich werden sie bei Bedarf vom Server geladen.

| Parameter / Schalter    | Beschreibung                                                                                                                                                                     |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `-NextcloudPath <Pfad>` | Vorhandener Synchronisierungsordner. Ohne Angabe wird `%USERPROFILE%\Nextcloud` verwendet, falls vorhanden; andernfalls erscheint eine Pfadabfrage.                              |
| `-Folders <Namen>`      | Auswahl aus `Desktop`, `Documents`, `Pictures`, `Music` und `Videos`. Standardmäßig alle fünf.                                                                                   |
| `-WhatIf`               | Zeigt geplante Löschungen an, ohne Dateien zu ändern.                                                                                                                            |
| `-Confirm`              | Fragt vor dem Entfernen passender Dateien und Unterordner jedes ausgewählten Ordners nach. Die erforderliche Bestätigung der abgeschlossenen Synchronisierung bleibt interaktiv. |
| `-EnglishOutput`        | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache.                                                                                                    |

Beispiele:

```powershell
.\Remove-MigratedUserData.ps1 -NextcloudPath 'D:\Nextcloud' -Folders Documents,Pictures -WhatIf
.\Remove-MigratedUserData.ps1 -NextcloudPath 'D:\Nextcloud' -Folders Documents,Pictures
```

Der zweite Befehl löscht nach der erforderlichen Bestätigung der abgeschlossenen Synchronisierung; mit `-Confirm` werden
zusätzlich Rückfragen pro Ordner aktiviert.

## Gemeinsame PowerShell-Parameter

Beide Skripte verwenden `SupportsShouldProcess`; daher stehen `-WhatIf` und `-Confirm` zur Verfügung. Außerdem unterstützen sie die üblichen Parameter `-Verbose`, `-Debug`, `-ErrorAction` und `-WarningAction`.

## Sicherheit und Verhalten

- Das Kopierskript verschiebt oder löscht niemals Quelldaten.
- Zielinhalte werden weder gespiegelt noch bereinigt.
- Das Kopierskript prüft nur Leseberechtigungen. Dateien, deren SHA-256-Hash bereits irgendwo im jeweiligen Zielordner vorkommt, werden ohne Einzelwarnung übersprungen.
- Unmittelbar vor jeder Löschung vergleicht das Bereinigungsskript den lokalen Hash erneut mit den zuvor gefundenen passenden Zieldateien. Geänderte, fehlende oder nicht mehr inhaltsgleiche Dateien bleiben erhalten.
- Dateiübertragungen erfolgen in Blöcken mit Wiederholungsversuchen in `.part`-Zwischendateien im selben Ordner. Quell-
  und Zwischendatei werden vor der Veröffentlichung per Hash geprüft. Die fertige Datei wird anschließend verschoben
  oder ersetzt atomar die Zieldatei, damit der Synchronisierungsclient keine unvollständige endgültige Datei sieht.
- Die Bestätigung der Synchronisierung ist eine Nutzeraussage. Das Bereinigungsskript kann den Serverzustand nicht unabhängig prüfen.
- Das Projekt steht unter der [MIT-Lizenz](../LICENSE.md).
- Hinweise zum Mitwirken stehen in [CONTRIBUTING.md](../CONTRIBUTING.md).
