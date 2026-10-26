# Git-Konfigurationswerkzeug

> Englische Version: [README.md](README.md)

`Initialize-GitConfiguration.ps1` richtet die Git-Autor-Identität (und optional gängige Standardeinstellungen) in der lokalen `.git/config` eines Repositorys oder in der globalen Benutzerkonfiguration ein. Name und E-Mail werden nicht im Skript hinterlegt; bereits im Zielbereich gesetzte Werte werden nicht überschrieben.

## Schnellstart

1. Wechsle in ein Verzeichnis innerhalb des Git-Repositorys, das konfiguriert werden soll.
2. Starte das Skript:

```powershell
.\Initialize-GitConfiguration.ps1
```

3. Für jeden Identitätswert zeigt das Skript eine nummerierte Liste gefundener Möglichkeiten plus eigener Eingabe. Eine vorhandene Git-Einstellung steht an erster Stelle, die Eingabetaste (Standard: Auswahl 1) behält sie bei:

- **Name:** vorhandene Git-Einstellungen (lokal, global, System), Anzeigename aus Active Directory bzw. Windows oder ein eigener Wert.
- **E-Mail:** vorhandene Git-Einstellungen, das Active-Directory-Attribut `mail` (domänenverbundene Rechner), der Benutzerprinzipalname (Active Directory / Entra ID), das angemeldete Microsoft-Konto oder ein eigener Wert.

## Abhängigkeiten einrichten

Git muss installiert und über `PATH` erreichbar sein. Administratorrechte sind nicht erforderlich. Verzeichnisabfragen haben ein kurzes Zeitlimit und werden übersprungen, wenn kein Verzeichnis erreichbar ist.

## Skripte und Schalter

### `Remove-ObsoleteGitBranches.ps1`

Starte das Skript in einem beliebigen Verzeichnis des Repositorys, dessen lokale Branches bereinigt werden sollen. Der
lokale Branch `main` und der aktuell ausgecheckte Branch sind geschützt. Ein lokaler Branch gilt als veralteter
Kandidat, wenn **mindestens eine** dieser Bedingungen zutrifft: Er ist nicht weiter als der lokale `main`-Branch, er ist
nicht weiter als sein verfügbarer Upstream oder er ist vollständig in den aktuell ausgecheckten Branch integriert. Das
Skript zeigt die geplanten Löschungen an und fragt nach Bestätigung. Vor dem Löschen wird geprüft, ob sich der Branch
seit der Analyse geändert hat.

| Parameter / Schalter | Beschreibung                                                                  |
|----------------------|-------------------------------------------------------------------------------|
| `-WhatIf`            | Zeigt die geplanten Löschungen an, ohne Branches zu entfernen.                |
| `-Confirm`           | Fragt vor dem Entfernen jedes Branches nach.                                  |
| `-Confirm:$false`    | Unterdrückt Rückfragen beim Entfernen.                                        |
| `-EnglishOutput`     | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache. |

Beispiele:

```powershell
.\Remove-ObsoleteGitBranches.ps1
.\Remove-ObsoleteGitBranches.ps1 -WhatIf
.\Remove-ObsoleteGitBranches.ps1 -Confirm:$false
```

Das Skript verwendet nur die lokalen Referenzen und führt keinen Fetch aus. Gibt es keinen verfügbaren Upstream-Branch,
wird dieser Upstream-Vergleich nicht angewendet. Das Skript wechselt niemals den Branch und ändert keine Dateien;
gestagte, nicht gestagte und nicht versionierte Änderungen im Arbeitsbereich bleiben unberührt. Git kann Branches, die
in einem anderen Worktree ausgecheckt sind, nicht entfernen; solche Fälle werden als Fehler gemeldet.

### `Initialize-GitConfiguration.ps1`

Das Skript läuft standardmäßig interaktiv. Die folgenden Schalter überspringen die Abfragen oder ändern den Zielbereich.

| Parameter / Schalter | Beschreibung |
| --- | --- |
| `-RepositoryPath <Pfad>` | Verzeichnis innerhalb des Repositorys (Bereich Local). Standard ist das aktuelle Verzeichnis. |
| `-Scope <Local\|Global>` | Zielbereich der Einstellungen. Standard `Local`; `Global` gilt für alle Repositorys des aktuellen Benutzers. |
| `-Name <Name>` | Wert für `user.name`; überspringt die interaktive Auswahl. |
| `-Email <Adresse>` | Wert für `user.email`; überspringt die interaktive Auswahl. |
| `-EnglishOutput` | Erzwingt englische Konsolenausgabe unabhängig von der Windows-Anzeigesprache. |

Beispiele:

```powershell
.\Initialize-GitConfiguration.ps1 -RepositoryPath 'C:\src\projekt'
.\Initialize-GitConfiguration.ps1 -Name 'Max Mustermann' -Email 'max@example.com'
.\Initialize-GitConfiguration.ps1 -Scope Global
.\Initialize-GitConfiguration.ps1 -EnglishOutput
```

#### Empfohlene Einstellungen

| Einstellung | Wert | Zweck |
| --- | --- | --- |
| `init.defaultBranch` | `main` | Standard-Branchname für neue Repositorys. |
| `core.autocrlf` | `true` | Zeilenenden-Konvertierung unter Windows. |
| `core.longpaths` | `true` | Erlaubt Pfade über 260 Zeichen. |
| `fetch.prune` | `true` | Entfernt veraltete Remote-Tracking-Branches. |
| `pull.rebase` | `false` | Explizites Merge-Verhalten bei Pull. |
| `push.autoSetupRemote` | `true` | Der erste Push legt den Upstream automatisch an. |
| `format.signOff` | `true` | Fügt Patches aus `git format-patch` ein `Signed-off-by` hinzu. |
| `alias.cs` | `commit --signoff` | `git cs` erstellt einen Commit mit Sign-off. Git kennt keine Einstellung, die jeden Commit automatisch signiert. |

Vor jeder Abfrage gibt das Skript eine ausführliche Erklärung der Einstellung aus und zeigt die Empfehlung, falls dein aktueller Wert abweicht. Die Tabelle oben fasst sie zusammen. Vorhandene Werte ändern sich nie ohne deine Eingabe: Jede empfohlene Einstellung wird einzeln bestätigt. Die Eingabetaste übernimmt den Standard (den im Zielbereich bereits gesetzten Wert, sonst die Empfehlung), die Eingabe eines der aufgelisteten Werte (je Zeile als `[Wert] Erklärung`) wählt ihn, freie Einstellungen (`init.defaultBranch`, `alias.cs`) akzeptieren auch jeden anderen Text, `-` lässt die Einstellung unverändert. Das Skript ist idempotent: Wer durchgehend die Eingabetaste drückt, ändert bei einem erneuten Lauf nichts.

## Gemeinsame PowerShell-Parameter

Das Skript unterstützt die üblichen Parameter `-Verbose`, `-Debug`, `-ErrorAction` und `-WarningAction`. Es implementiert kein `-WhatIf` und kein `-Confirm`.

## Sicherheit und Verhalten

- Commit-E-Mail-Adressen sind in der Historie sichtbar; verwende bei öffentlichen Repositorys eine öffentliche oder No-Reply-Adresse.

- Das Projekt steht unter der [MIT-Lizenz](../LICENSE.md).
- Hinweise zum Mitwirken stehen in [CONTRIBUTING.md](../CONTRIBUTING.md).
