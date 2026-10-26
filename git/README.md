# Git configuration tool

> Deutsche Version: [README.de.md](README.de.md)

`Initialize-GitConfiguration.ps1` initializes the Git author identity (and optionally common standard settings) in a repository's local `.git/config` or in the user's global configuration. It never stores a name or email in the script and does not overwrite existing values in the target scope.

## Quick start

1. Change into a directory inside the Git repository you want to configure.
2. Run the script:

```powershell
.\Initialize-GitConfiguration.ps1
```

3. For each identity value, the script shows a numbered list of discovered choices plus a custom entry. An existing Git setting is listed first, so pressing Enter (default: choice 1) keeps it:

- **Name:** existing Git settings (local, global, system), the Active Directory or Windows display name, or a custom value.
- **Email:** existing Git settings, the Active Directory `mail` attribute (domain-joined computers), the user principal name (Active Directory / Entra ID), the signed-in Microsoft account, or a custom value.

## Dependency setup

Git must be installed and available on `PATH`. No administrator privileges are needed. Directory lookups time out quickly and are skipped when no directory is reachable.

## Scripts and switches

### `Remove-ObsoleteGitBranches.ps1`

Run this script from any directory inside the repository whose local branches you want to clean up. It protects the
local `main` branch and the currently checked-out branch. A local branch is an obsolete candidate if **any** of these
conditions is true: it is not ahead of local `main`, it is not ahead of its available upstream, or it is fully merged
into the currently checked-out branch. The script previews and confirms removals, and checks that a branch has not moved
since analysis before deleting it.

| Parameter / switch | Description                                                                  |
|--------------------|------------------------------------------------------------------------------|
| `-WhatIf`          | Lists the branch removals that would be attempted without deleting branches. |
| `-Confirm`         | Prompts before each branch removal.                                          |
| `-Confirm:$false`  | Suppresses removal prompts.                                                  |
| `-EnglishOutput`   | Forces English console output regardless of the Windows UI language.         |

Examples:

```powershell
.\Remove-ObsoleteGitBranches.ps1
.\Remove-ObsoleteGitBranches.ps1 -WhatIf
.\Remove-ObsoleteGitBranches.ps1 -Confirm:$false
```

The script uses the current local refs and does not fetch from remotes. If a branch has no available upstream ref, the
upstream comparison is not used. It never checks out branches or changes files, so staged, unstaged, and untracked
working-tree changes are left untouched. Branches checked out in another worktree cannot be removed by Git and are
reported as failures.

### `Initialize-GitConfiguration.ps1`

The script runs interactively by default. The switches below skip the prompts or change the target scope.

| Parameter / switch | Description |
| --- | --- |
| `-RepositoryPath <path>` | Directory inside the repository (Local scope). Defaults to the current directory. |
| `-Scope <Local\|Global>` | Where to write the settings. Defaults to `Local`; `Global` applies to all repositories of the current user. |
| `-Name <name>` | Value for `user.name`; skips the interactive choice. |
| `-Email <address>` | Value for `user.email`; skips the interactive choice. |
| `-EnglishOutput` | Forces English console output regardless of the Windows UI language. |

Examples:

```powershell
.\Initialize-GitConfiguration.ps1 -RepositoryPath 'C:\src\project'
.\Initialize-GitConfiguration.ps1 -Name 'Jane Doe' -Email 'jane@example.com'
.\Initialize-GitConfiguration.ps1 -Scope Global
.\Initialize-GitConfiguration.ps1 -EnglishOutput
```

#### Recommended settings

| Setting | Value | Purpose |
| --- | --- | --- |
| `init.defaultBranch` | `main` | Default branch name for new repositories. |
| `core.autocrlf` | `true` | Windows line-ending conversion. |
| `core.longpaths` | `true` | Allows paths longer than 260 characters. |
| `fetch.prune` | `true` | Removes stale remote-tracking branches. |
| `pull.rebase` | `false` | Explicit merge behavior on pull. |
| `push.autoSetupRemote` | `true` | First push sets the upstream automatically. |
| `format.signOff` | `true` | Adds `Signed-off-by` to patches from `git format-patch`. |
| `alias.cs` | `commit --signoff` | `git cs` creates a signed-off commit. Git has no setting that signs off every commit automatically. |

Before each prompt the script prints a detailed explanation of the setting and shows the recommendation when your current value differs. The table above summarizes them. Existing values are never changed without your input: each setting is confirmed individually. Pressing Enter accepts the default (the value already set in the target scope, otherwise the recommendation), typing one of the listed values (shown one per line as `[value] explanation`) selects it, free-form settings (`init.defaultBranch`, `alias.cs`) also accept any other text, and `-` leaves the setting untouched. The operation is idempotent: pressing Enter throughout changes nothing on a repeated run.

## Shared PowerShell parameters

The script supports the common parameters `-Verbose`, `-Debug`, `-ErrorAction` and `-WarningAction`. It does not implement `-WhatIf` or `-Confirm`.

## Safety and behavior

- Commit emails are visible in the history; choose a public or no-reply address for public repositories.

- The project is licensed under the [MIT License](../LICENSE.md).
- Contribution notes are in [CONTRIBUTING.md](../CONTRIBUTING.md).
