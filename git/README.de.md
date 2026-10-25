# Git-Konfigurationswerkzeug

`Initialize-GitConfiguration.ps1` richtet die Git-Autor-Identität (und optional gängige Standardeinstellungen) in der lokalen `.git/config` eines Repositorys oder in der globalen Benutzerkonfiguration ein. Name und E-Mail werden nicht im Skript hinterlegt; bereits im Zielbereich gesetzte Werte werden nicht überschrieben.

## Verwendung

Starte das Skript innerhalb eines Git-Repositorys:

```powershell
.\Initialize-GitConfiguration.ps1
```

Für jeden Identitätswert zeigt das Skript eine nummerierte Liste gefundener Möglichkeiten plus eigener Eingabe. Eine vorhandene Git-Einstellung steht an erster Stelle, die Eingabetaste (Standard: Auswahl 1) behält sie bei:

- **Name:** vorhandene Git-Einstellungen (lokal, global, System), Anzeigename aus Active Directory bzw. Windows oder ein eigener Wert.
- **E-Mail:** vorhandene Git-Einstellungen, das Active-Directory-Attribut `mail` (domänenverbundene Rechner), der Benutzerprinzipalname (Active Directory / Entra ID), das angemeldete Microsoft-Konto oder ein eigener Wert.

Git muss installiert und über `PATH` erreichbar sein. Administratorrechte sind nicht erforderlich. Verzeichnisabfragen haben ein kurzes Zeitlimit und werden übersprungen, wenn kein Verzeichnis erreichbar ist.

| Parameter | Beschreibung |
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

## Empfohlene Einstellungen

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

Das Skript unterstützt PowerShell-Standardparameter wie `-Verbose`, `-Debug` und `-ErrorAction`. Commit-E-Mail-Adressen sind in der Historie sichtbar; verwende bei öffentlichen Repositorys eine öffentliche oder No-Reply-Adresse.

Siehe [Mitwirken](../CONTRIBUTING.md) und die [MIT-Lizenz](../LICENSE.md).
