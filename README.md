# scriptbox

> Deutsche Version: [README.de.md](README.de.md)

> [!CAUTION]
> 🔴 **ALPHA: This project is in an alpha state. Do NOT run these scripts on productive data.** Test only with copies of your files and keep backups.

Small PowerShell utilities for everyday tasks, including PDF processing, Git configuration, and copying and cleaning up local Nextcloud data.

## PDF tools

Available tools:

- `Initialize-PdfProcessor.ps1` — checks and installs PDF-processing dependencies.
- `Optimize-ScannedPdfs.ps1` — processes scanned PDFs, adds OCR where needed, corrects page orientation, and optionally compresses PDFs.
- `Find-PdfsWithoutTextLayer.ps1` — reports PDFs with missing or partially missing text layers.
- `Clear-OriginalPdfBackups.ps1` — removes `_orig` backups only when the corresponding processed PDF exists.

| Script | Parameters and switches |
| --- | --- |
| `Initialize-PdfProcessor.ps1` | `-EnglishOutput`. Internal hidden parameters: `-ElevatedChild`, `-RuntimePythonPath`. |
| `Optimize-ScannedPdfs.ps1` | `-InputPath <path>`, `-Language <codes>`, `-JpegQuality <1-100>`, `-GhostscriptDpi <50-1200>`, `-NoDeskew`, `-NoRotationOfPages`, `-ProcessDigitallyBornPdfs`, `-NoGhostscript`, `-ReplaceOriginal`, `-ForceReprocess`, `-EnglishOutput`. |
| `Find-PdfsWithoutTextLayer.ps1` | `-InputPath <path>`, `-EnglishOutput`. |
| `Clear-OriginalPdfBackups.ps1` | `-InputPath <folder>`, `-WhatIf`, `-Confirm` (use `-Confirm:$false` to suppress confirmation), `-EnglishOutput`. |

Scanned-PDF processing uses best-effort, stateless classification: digitally born PDFs are skipped by default, and no persistent marker is written beside them. Scanned PDFs with existing OCR are reprocessed automatically so deskew and rotation correction can run; OCR is regenerated and page content is rasterized. `-ProcessDigitallyBornPdfs` opts into processing digitally born PDFs. Classification is heuristic and may not identify mixed or unusual PDFs correctly.

See the [PDF tools guide](pdf/README.md) for parameter behavior, examples, setup, dependencies, and safety notes.

Run scripts from PowerShell. The scripts select German console messages on a German Windows UI and English messages otherwise; `-EnglishOutput` forces English.

## Testing

The GitHub Actions workflow runs `tests/Invoke-Tests.ps1` with Windows PowerShell 5.1 and PowerShell 7 for pull requests targeting `main`. To run the same test suite locally, use `.\tests\Invoke-Tests.ps1` from the repository root; Pester 5 or later is required.

## Git configuration

`git/Initialize-GitConfiguration.ps1` sets the Git author identity (local or global) by offering discovered names and emails (existing Git settings, Active Directory / Windows account data, Microsoft account) or a custom value, and confirms recommended standard settings one by one. Existing values are the defaults and nothing is stored in the script.

| Script | Parameters and switches |
| --- | --- |
| `Initialize-GitConfiguration.ps1` | `-RepositoryPath <path>`, `-Scope <Local\|Global>`, `-Name <name>`, `-Email <address>`, `-EnglishOutput`. |

See the [Git tool guide](git/README.md) for parameters and examples.

## Nextcloud file copy and local cleanup

The workflow uses two scripts: `nextcloud/Copy-UserDataToNextcloud.ps1` copies selected Windows user folders into existing Nextcloud destination folders and never deletes source data. After synchronization to the server is complete, `nextcloud/Remove-MigratedUserData.ps1` can delete local files whose SHA-256 hash matches a file in the corresponding Nextcloud destination folder, as well as empty local subfolders when the corresponding Nextcloud folder exists. Before deletion, the user confirms that synchronization is complete and approves cleanup separately for each main folder.

| Script | Parameters and switches |
| --- | --- |
| `Copy-UserDataToNextcloud.ps1` | `-NextcloudPath <path>`, `-Folders <names>`, `-WhatIf`, `-Confirm`, `-EnglishOutput`. Copies only; source files are never deleted. |
| `Remove-MigratedUserData.ps1` | `-NextcloudPath <path>`, `-Folders <names>`, `-WhatIf`, `-Confirm`, `-EnglishOutput`. Deletes local files with matching SHA-256 hashes and empty subfolders when the corresponding Nextcloud folder exists. |

See the [Nextcloud tool guide](nextcloud/README.md) for details and examples.

## Open issues

Planned work is listed in [open-issues.md](open-issues.md).

The project is licensed under the [MIT License](LICENSE.md).
See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidance.
