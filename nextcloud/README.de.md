# Nextcloud-Dateikopie und lokale Bereinigung

Der Ablauf ist in zwei getrennte Skripte aufgeteilt:

1. [`Copy-UserDataToNextcloud.ps1`](./Copy-UserDataToNextcloud.ps1) kopiert ausgewählte Windows-Benutzerordner in bereits vorhandene Nextcloud-Zielordner. Das Skript verschiebt und löscht niemals Quelldaten.
2. Aktiviere anschließend den Nextcloud-Synchronisierungsclient wieder und warte, bis die Synchronisierung vollständig abgeschlossen ist.
3. [`Remove-MigratedUserData.ps1`](./Remove-MigratedUserData.ps1) kann danach lokale Dateien löschen, wenn ihr SHA-256-Hash mit dem einer Datei im zugeordneten Nextcloud-Zielordner übereinstimmt. Leere lokale Unterordner werden ebenfalls gelöscht, sofern der entsprechende Unterordner in Nextcloud existiert. Das Skript fragt zuerst nach der abgeschlossenen Synchronisierung, zeigt für jeden Hauptordner die Anzahl und Gesamtgröße der passenden Dateien sowie die Anzahl der entsprechenden Unterordner und verlangt eine separate Bestätigung pro Ordner.

Die Skripte ermitteln die tatsächlichen Windows-Spezialordner des aktuellen Benutzers, auch wenn diese umgeleitet sind. `Pictures` wird dem Nextcloud-Ordner `Photos` zugeordnet. Der Nextcloud-Stammordner und jeder ausgewählte Zielordner müssen bereits existieren; benötigte Unterordner werden beim Kopieren angelegt. Dateien im Ziel werden weder gespiegelt noch entfernt.

Das Kopierskript prüft nur Leseberechtigungen. Dateien, deren SHA-256-Hash bereits irgendwo im jeweiligen Nextcloud-Zielordner vorkommt, werden ohne Einzelwarnung übersprungen. Die Inventarisierung berücksichtigt Nextcloud-Platzhalter und durchläuft keine symbolischen Links oder Junctions; für den Hash-Vergleich werden Platzhalter bei Bedarf vom Server geladen. Die übrigen Dateien kopiert Robocopy im fortsetzbaren Modus mit Wiederholungsversuchen; während der Übertragung wird ein Fortschrittsbalken angezeigt.

Die Bestätigung der Synchronisierung ist eine Nutzeraussage; das Löschskript kann den Serverzustand nicht selbst prüfen. Vor jeder einzelnen Dateilöschung vergleicht es den lokalen Hash erneut mit allen zuvor gefundenen passenden Zieldateien. Geänderte, fehlende oder nicht mehr inhaltsgleiche Dateien bleiben lokal erhalten. Gelöscht werden nur passende lokale Dateien und leere Unterordner, für die ein gleichnamiger Nextcloud-Unterordner existiert. Die ausgewählten Hauptordner, nicht passende Dateien und ausgeschlossene Systemartefakte bleiben bestehen. Symbolische Links und Junctions werden nicht durchlaufen. Nextcloud-Platzhalter (virtuelle Dateien) werden berücksichtigt; für den Hash-Vergleich werden sie bei Bedarf vom Server geladen.

`-WhatIf` zeigt geplante Kopier- beziehungsweise Löschaktionen an, ohne Dateien zu ändern.

## Parameter

| Parameter / Schalter | Beschreibung |
| --- | --- |
| `-NextcloudPath <Pfad>` | Vorhandener Synchronisierungsordner. Ohne Angabe wird `%USERPROFILE%\Nextcloud` verwendet, falls vorhanden; andernfalls erscheint eine Pfadabfrage. |
| `-Folders <Namen>` | Auswahl aus `Desktop`, `Documents`, `Pictures`, `Music` und `Videos`. Standardmäßig alle fünf. |
| `-WhatIf` | Zeigt geplante Aktionen an, ohne Dateien zu ändern. |
| `-Confirm` | Verwendet die PowerShell-Bestätigungsabfrage für Änderungen. Ohne diesen Schalter fragen die Skripte ebenfalls interaktiv nach. |
| `-EnglishOutput` | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache. |

## Beispiele

Kopiervorgang zunächst ohne Änderungen prüfen:

```powershell
.\Copy-UserDataToNextcloud.ps1 -WhatIf
```

Nur Dokumente und Bilder nach `D:\Nextcloud` kopieren:

```powershell
.\Copy-UserDataToNextcloud.ps1 -NextcloudPath 'D:\Nextcloud' -Folders Documents,Pictures
```

Nach abgeschlossener Serversynchronisierung passende lokale Dokumente und Bilder anzeigen:

```powershell
.\Remove-MigratedUserData.ps1 -NextcloudPath 'D:\Nextcloud' -Folders Documents,Pictures -WhatIf
```

Nach Prüfung und Bestätigung passende lokale Dateien löschen:

```powershell
.\Remove-MigratedUserData.ps1 -NextcloudPath 'D:\Nextcloud' -Folders Documents,Pictures
```

Beide Skripte benötigen Windows PowerShell 5.1 oder neuer. Administratorrechte oder zusätzliche Module sind nicht erforderlich.

Siehe [Mitwirken](../CONTRIBUTING.md) und die [MIT-Lizenz](../LICENSE.md).
