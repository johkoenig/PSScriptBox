# Nextcloud file copy and local cleanup

> Deutsche Version: [README.de.md](README.de.md)

This folder contains two PowerShell scripts: one copies selected Windows user folders into an existing Nextcloud sync folder, the other removes local copies after synchronization has completed. Use Windows PowerShell 5.1 or later from a regular user session. No administrator rights or third-party modules are required.

## Quick start

1. Open PowerShell in this folder.
2. Preview the copy operation:

   ```powershell
   .\Copy-UserDataToNextcloud.ps1 -WhatIf
   ```

3. Run the copy, for example into `D:\Nextcloud`:

   ```powershell
   .\Copy-UserDataToNextcloud.ps1 -NextcloudPath 'D:\Nextcloud'
   ```

4. Re-enable the Nextcloud sync client and wait until synchronization has fully completed.
5. Preview the local cleanup, then run it without `-WhatIf` after reviewing the output:

   ```powershell
   .\Remove-MigratedUserData.ps1 -NextcloudPath 'D:\Nextcloud' -WhatIf
   ```

## Dependency setup

The Nextcloud sync client must be installed and configured. The synchronization folder is `%USERPROFILE%\Nextcloud` by
default, or the path given with `-NextcloudPath`. The Nextcloud root and every selected destination folder must already
exist; nested directories are created as needed. File copying uses built-in PowerShell and .NET APIs; no external copy
utility is required.

## Scripts and switches

### `Copy-UserDataToNextcloud.ps1`

Copies the selected user folders (Desktop, Documents, Pictures, Music, Videos) into matching destinations beneath the Nextcloud folder. `Pictures` maps to `Photos`. The script never moves or deletes source data, and it never mirrors or purges destination content.

The scripts discover the current user's actual Windows special-folder paths, including redirected folders.

The copy script checks read access only. Files whose SHA-256 hash already exists anywhere in the corresponding Nextcloud
destination folder are skipped without a per-file warning. Its inventory includes Nextcloud virtual-file placeholders
and does not traverse symbolic links or junctions; hashing a placeholder downloads its content from the server if it is
not stored locally. Remaining files are copied in chunks with retries and a progress bar. Each transfer uses a
same-directory `.part` file, verifies the source and staged hashes, then moves or atomically replaces the final file
only after the copy completes.

| Parameter / switch | Description |
| --- | --- |
| `-NextcloudPath <path>` | Existing synchronization directory. If omitted, uses `%USERPROFILE%\Nextcloud` when present; otherwise prompts for a path. |
| `-Folders <names>` | Selects from `Desktop`, `Documents`, `Pictures`, `Music`, and `Videos`. Defaults to all five. |
| `-WhatIf` | Previews planned copy actions without changing files. |
| `-Confirm` | Uses PowerShell confirmation prompts for changes. The script also prompts interactively without this switch. |
| `-EnglishOutput` | Forces English console output regardless of the Windows UI language. |

Examples:

```powershell
.\Copy-UserDataToNextcloud.ps1 -WhatIf
.\Copy-UserDataToNextcloud.ps1 -NextcloudPath 'D:\Nextcloud' -Folders Documents,Pictures
```

### `Remove-MigratedUserData.ps1`

Removes local files whose SHA-256 hash matches a file in the corresponding Nextcloud destination folder, and deletes empty local subfolders when the corresponding Nextcloud subfolder exists. The script first asks you to confirm that synchronization is complete, shows the matching file count, total size, and corresponding subfolder count for each main folder, and requests separate approval per folder.

The synchronization acknowledgement is a user confirmation; the cleanup script cannot independently verify the server state. Immediately before each file deletion, it rechecks the local hash against the matching destination files discovered earlier. Changed, missing, or no-longer-identical files are retained locally. It removes only matching local files and empty subfolders whose corresponding Nextcloud subfolder exists; selected main folders, non-matching files, and excluded system artifacts are retained. Symbolic links and junctions are not traversed. Nextcloud virtual files are included; hashing them downloads their content from the server if it is not stored locally.

| Parameter / switch | Description |
| --- | --- |
| `-NextcloudPath <path>` | Existing synchronization directory. If omitted, uses `%USERPROFILE%\Nextcloud` when present; otherwise prompts for a path. |
| `-Folders <names>` | Selects from `Desktop`, `Documents`, `Pictures`, `Music`, and `Videos`. Defaults to all five. |
| `-WhatIf` | Previews planned deletions without changing files. |
| `-Confirm` | Uses PowerShell confirmation prompts for changes. The script also prompts interactively without this switch. |
| `-EnglishOutput` | Forces English console output regardless of the Windows UI language. |

Examples:

```powershell
.\Remove-MigratedUserData.ps1 -NextcloudPath 'D:\Nextcloud' -Folders Documents,Pictures -WhatIf
.\Remove-MigratedUserData.ps1 -NextcloudPath 'D:\Nextcloud' -Folders Documents,Pictures
```

The second command deletes only after the review and confirmation prompts.

## Shared PowerShell parameters

Both scripts use `SupportsShouldProcess`, so `-WhatIf` and `-Confirm` are available. They also support the common parameters `-Verbose`, `-Debug`, `-ErrorAction`, and `-WarningAction`.

## Safety and behavior

- Source data is never moved or deleted by the copy script.
- Destination content is never mirrored or purged.
- The copy script checks read access only. Files whose SHA-256 hash already exists anywhere in the corresponding destination folder are skipped without a per-file warning.
- Immediately before each deletion, the cleanup script rechecks the local hash against the matching destination files found earlier. Changed, missing, or no-longer-identical files are retained.
- File transfers use chunked, retryable copies into same-directory `.part` staging files. The source and staged hashes
  are verified before the completed file is moved or atomically replaces the final destination, so the sync client does
  not see an in-progress final file.
- The synchronization acknowledgement is a user statement. The cleanup script cannot verify the server state independently.
- The project is licensed under the [MIT License](../LICENSE.md).
- Contribution guidance is in [CONTRIBUTING.md](../CONTRIBUTING.md).
