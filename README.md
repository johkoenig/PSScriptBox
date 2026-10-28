# PSScriptBox

> Deutsche Version: [README.de.md](README.de.md)

> [!CAUTION]
> 🔴 **ALPHA: Do not run these scripts on productive data.** Test only with copies of your files and keep backups.

PSScriptBox is a collection of PowerShell utilities for PDF and media processing, Git setup, and local Nextcloud
workflows.

## PDF tools

These scripts help make PDFs searchable, reduce file size, find missing text layers, and manage backups. See
the [PDF tools guide](pdf/README.md) for setup, examples, and safety details.

| Script                          | Purpose                                             |
|---------------------------------|-----------------------------------------------------|
| `ConvertTo-SearchablePdf.ps1`   | Add OCR to scanned PDFs and correct page rotation.  |
| `Optimize-PdfSize.ps1`          | Reduce PDF size by downsampling images.             |
| `Find-PdfsWithoutTextLayer.ps1` | Find PDFs with missing or incomplete text layers.   |
| `Remove-PdfBackups.ps1`         | Remove `_orig` backups when a processed PDF exists. |
| `Restore-PdfOriginals.ps1`      | Restore PDFs from matching `_orig` backups.         |

## Media tools

Process media files by reducing their size, restoring dates, and managing backups or Live Photos. See
the [Media tools guide](media/README.md) for dependencies, examples, and behavior details.

| Script                    | Purpose                                                        |
|---------------------------|----------------------------------------------------------------|
| `Optimize-MediaSize.ps1`  | Reduce the size of supported videos and JPEG photos.           |
| `Remove-MediaBackups.ps1` | Remove `_orig` backups when a processed file exists.           |
| `Remove-LivePhotos.ps1`   | Remove MOV videos that have a matching JPG photo.              |
| `Restore-MediaDate.ps1`   | Restore media dates and rename files using the recovered date. |

## Git tools

Configure Git identity and recommended settings, or clean up obsolete local branches. See
the [Git tools guide](git/README.md) for examples and details.

| Script                            | Purpose                                                                                 |
|-----------------------------------|-----------------------------------------------------------------------------------------|
| `Initialize-GitConfiguration.ps1` | Set a local or global Git identity and configure recommended settings.                  |
| `Remove-ObsoleteGitBranches.ps1`  | Find and remove obsolete local branches while protecting `main` and the current branch. |

## Nextcloud

Copy selected Windows user folders to existing Nextcloud folders, then optionally clean up verified local copies after
synchronization. See the [Nextcloud tools guide](nextcloud/README.md) for details.

| Script                         | Purpose                                                     |
|--------------------------------|-------------------------------------------------------------|
| `Copy-UserDataToNextcloud.ps1` | Copy selected folders without deleting source files.        |
| `Remove-MigratedUserData.ps1`  | Remove local files verified against their Nextcloud copies. |

## Testing

Run the test suite with `.\tests\Invoke-Tests.ps1` from the repository root; Pester 5 or later is required. Add
`-Coverage` to report executable-line coverage for internal helpers, list uncovered line ranges, and print a coverage
summary. Fully covered files are omitted from the listing. GitHub Actions also runs the tests on Windows PowerShell 5.1
and PowerShell 7.

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md) for contribution steps and [AGENTS.md](AGENTS.md) for repository-specific
development and documentation guidance.

## License

PSScriptBox is licensed under the [MIT License](LICENSE.md).
