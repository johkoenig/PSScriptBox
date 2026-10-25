# Nextcloud file copy and local cleanup

The workflow uses two separate scripts:

1. [`Copy-UserDataToNextcloud.ps1`](./Copy-UserDataToNextcloud.ps1) copies selected Windows user folders into existing Nextcloud destination folders. It never moves or deletes source data.
2. Re-enable the Nextcloud sync client and wait until synchronization has fully completed.
3. [`Remove-MigratedUserData.ps1`](./Remove-MigratedUserData.ps1) can then delete local files when their SHA-256 hash matches a file in the corresponding Nextcloud destination folder. It also deletes empty local subfolders when the corresponding subfolder exists in Nextcloud. It first asks you to confirm that synchronization is complete, shows the matching file count and total size plus the count of corresponding subfolders for each main folder, and requests separate approval for each folder.

The scripts discover the current user's actual Windows special-folder paths, including redirected folders. `Pictures` maps to the Nextcloud `Photos` folder. The Nextcloud root and every selected destination folder must already exist; nested directories are created as needed. Destination content is not mirrored or purged.

The copy script checks read access only. Files whose SHA-256 hash already exists anywhere in the corresponding Nextcloud destination folder are skipped without a per-file warning. Its inventory includes Nextcloud virtual-file placeholders and does not traverse symbolic links or junctions; hashing a placeholder downloads its content from the server if it is not stored locally. Robocopy transfers the remaining files in restartable mode with retries and displays a progress bar.

The synchronization acknowledgement is a user confirmation; the cleanup script cannot independently verify the server state. Immediately before each file deletion, it rechecks the local hash against the matching destination files discovered earlier. Changed, missing, or no-longer-identical files are retained locally. It removes only matching local files and empty subfolders whose corresponding Nextcloud subfolder exists; selected main folders, non-matching files, and excluded system artifacts are retained. Symbolic links and junctions are not traversed. Nextcloud virtual files are included; hashing them downloads their content from the server if it is not stored locally.

Use `-WhatIf` to preview copy or deletion actions without changing files.

## Parameters

| Parameter / switch | Description |
| --- | --- |
| `-NextcloudPath <path>` | Existing synchronization directory. If omitted, uses `%USERPROFILE%\Nextcloud` when present; otherwise prompts for a path. |
| `-Folders <names>` | Selects from `Desktop`, `Documents`, `Pictures`, `Music`, and `Videos`. Defaults to all five. |
| `-WhatIf` | Previews planned actions without changing files. |
| `-Confirm` | Uses PowerShell confirmation prompts for changes. Both scripts also prompt interactively without this switch. |
| `-EnglishOutput` | Forces English console output regardless of the Windows UI language. |

## Examples

Preview the copy operation:

```powershell
.\Copy-UserDataToNextcloud.ps1 -WhatIf
```

Copy only Documents and Pictures into `D:\Nextcloud`:

```powershell
.\Copy-UserDataToNextcloud.ps1 -NextcloudPath 'D:\Nextcloud' -Folders Documents,Pictures
```

After server synchronization is complete, preview matching local Documents and Pictures:

```powershell
.\Remove-MigratedUserData.ps1 -NextcloudPath 'D:\Nextcloud' -Folders Documents,Pictures -WhatIf
```

After review and confirmation, delete matching local files:

```powershell
.\Remove-MigratedUserData.ps1 -NextcloudPath 'D:\Nextcloud' -Folders Documents,Pictures
```

Both scripts require Windows PowerShell 5.1 or later. No administrator rights or third-party modules are required.

See [Contributing](../CONTRIBUTING.md) and the [MIT License](../LICENSE.md).
