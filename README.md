# scriptbox

> Deutsche Version: [README.de.md](README.de.md)

> [!CAUTION]
> 🔴 **ALPHA: This project is in an alpha state. Do NOT run these scripts on productive data.** Test only with copies of your files and keep backups.

Small PowerShell utilities for everyday tasks, including PDF processing, Git configuration, and copying and cleaning up local Nextcloud data.

## PDF tools

Available tools:

- `ConvertTo-SearchablePdf.ps1` — adds OCR and corrects scanned pages; digitally born PDFs are skipped, while encrypted
  and signed PDFs are reported as issues.
- `Optimize-PdfSize.ps1` — downsamples images to reduce PDF size, targeting 300 DPI and JPEG quality 75 by default;
  skips originals smaller than 1 MB.
- `Find-PdfsWithoutTextLayer.ps1` — reports PDFs with missing or partially missing text layers.
- `Remove-PdfBackups.ps1` — removes `_orig` backups only when the corresponding processed PDF exists.
- `Restore-PdfOriginals.ps1` — replaces processed PDFs with matching `_orig` originals.

| Script                          | Parameters and switches                                                                                                                                                                   |
|---------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `ConvertTo-SearchablePdf.ps1`   | `-InputPath <path>`, `-Language <codes>`, `-NoDeskew`, `-NoRotationOfPages`, `-ReplaceOriginal`, `-EnglishOutput`.                                                                        |
| `Optimize-PdfSize.ps1`          | `-InputPath <path>`, `-Dpi <50-1200>` (default `300`), `-JpegQuality <1-100>` (default `75`), `-MinFileSize <bytes>` (default `1MB`; `0` disables), `-ReplaceOriginal`, `-EnglishOutput`. |
| `Find-PdfsWithoutTextLayer.ps1` | `-InputPath <path>`, `-EnglishOutput`.                                                                                                                                                    |
| `Remove-PdfBackups.ps1`         | `-InputPath <folder>`, `-WhatIf`, `-Confirm` (use `-Confirm:$false` to suppress confirmation), `-EnglishOutput`.                                                                          |
| `Restore-PdfOriginals.ps1`      | `-InputPath <folder>`, `-WhatIf`, `-Confirm` (use `-Confirm:$false` to suppress confirmation), `-EnglishOutput`.                                                                          |

Scanned-PDF OCR uses best-effort, stateless classification: digitally born PDFs are skipped and no persistent marker is
written beside them. Existing OCR text is preserved; page rotation is detected separately and corrected without
regenerating the text layer. In partially OCRed scans, OCR is added only to pages without text. Ghostscript is needed
for rotation detection on pages that already have text. PDF-size optimization is a separate step and processes digitally
born PDFs too. For folder input, size optimization discovers all PDFs first and processes only files that meet the
minimum size. Encrypted and digitally signed PDFs cannot be processed and appear in the issue list. Routine skips and
unchanged files are counted in summaries but are not listed individually.

PDF scripts that need external tools check them individually and report missing
executables or Python modules with installation commands or download links.

See the [PDF tools guide](pdf/README.md) for parameter behavior, examples, setup, dependencies, and safety notes.

Run scripts from PowerShell. The scripts select German console messages on a German Windows UI and English messages otherwise; `-EnglishOutput` forces English.

## Media tools

`media/Optimize-MediaSize.ps1` re-encodes eligible `.mov` and `.mp4` videos as 720p H.265/HEVC MP4 using a 1.9 Mb/s
average video bitrate and 96 kb/s audio. Landscape output is limited to 1280x720 and portrait output to 720x1280; a
six-minute video is targeted at roughly 90 MB, though actual size varies. H.264 at or below 1.9 Mb/s and HEVC, AV1, or
VP9 sources are skipped. JPEG photos over 6 MB are proportionally scaled using an estimated output size of 5 MB and
re-encoded at high quality; actual size varies with image detail. Smaller photos are skipped. Results are kept only when
smaller, with supported file timestamps and embedded EXIF/XMP and container capture dates verified before replacement.
Per-track timestamps, Samsung maker-note `TimeStamp`, and non-capture EXIF `IFD0:ModifyDate` are excluded from
verification. By default, the original is saved as `<Name>_orig` with its original extension. Encoding is lossy and
cannot guarantee imperceptible changes. FFmpeg (including FFprobe) with `libx265` and MJPEG encoders, plus ExifTool,
must be available in `PATH`. `media/Remove-MediaBackups.ps1` interactively removes `_orig` backups only when their
processed counterpart exists; a MOV backup is matched to its MP4 output.
`media/Remove-LivePhotos.ps1` removes a MOV video only when a same-name JPG still image exists in the same folder; the
JPG is kept, and `.jpeg` is not considered a match. It supports `-WhatIf` and confirms each deletion.

`media/Restore-MediaDate.ps1` restores dates in this order: filename, EXIF `DateTimeOriginal`, `CreateDate`, then
`ModifyDate`. It renames supported media to `YY-MM-DD HH-mm-ss XXXX.ext`, updates filesystem creation and last-write
times plus supported embedded dates only when they differ from the selected date, and uses `-WhatIf` for preview.
Names that already match the pattern are retained. ExifTool must be available in `PATH`; Windows does not permit
setting the low-level NTFS change time.

| Script                    | Parameters and switches                                                           |
|---------------------------|-----------------------------------------------------------------------------------|
| `Optimize-MediaSize.ps1`  | `-InputPath <path>`, `-ReplaceOriginal`, `-WhatIf`, `-Confirm`, `-EnglishOutput`. |
| `Remove-MediaBackups.ps1` | `-InputPath <folder>`, `-WhatIf`, `-Confirm`, `-EnglishOutput`.                   |
| `Remove-LivePhotos.ps1`   | `-InputPath <folder>`, `-WhatIf`, `-Confirm`, `-EnglishOutput`.                   |
| `Restore-MediaDate.ps1`   | `-InputPath <folder>`, `-WhatIf`, `-Confirm`, `-EnglishOutput`.                   |

See the [Media tools guide](media/README.md) for examples, dependencies, and date-preservation limits.

## Git tools

`git/Initialize-GitConfiguration.ps1` sets the Git author identity (local or global) by offering discovered names and emails (existing Git settings, Active Directory / Windows account data, Microsoft account) or a custom value, and confirms recommended standard settings one by one. Existing values are the defaults and nothing is stored in the script.

`git/Remove-ObsoleteGitBranches.ps1` removes obsolete local branches from the repository at the current location. It
protects `main` and the current branch, and never modifies working-tree files. Without `-WhatIf`, it removes candidates
immediately without prompting; `-WhatIf` previews them.

| Script                            | Parameters and switches                                                                                   |
|-----------------------------------|-----------------------------------------------------------------------------------------------------------|
| `Initialize-GitConfiguration.ps1` | `-RepositoryPath <path>`, `-Scope <Local\|Global>`, `-Name <name>`, `-Email <address>`, `-EnglishOutput`. |
| `Remove-ObsoleteGitBranches.ps1`  | `-WhatIf`, `-EnglishOutput`.                                                                              |

An obsolete-branch candidate is not ahead of local `main`, not ahead of its available upstream, or fully merged into the
currently checked-out branch. The cleanup uses local refs only and supports `-WhatIf` for preview.

See the [Git tool guide](git/README.md) for parameters and examples.

## Nextcloud file copy and local cleanup

The workflow uses two scripts: `nextcloud/Copy-UserDataToNextcloud.ps1` copies selected Windows user folders into
existing Nextcloud destination folders and never deletes source data. File transfers are staged as `.part` files and
moved into their final names only when complete. After synchronization to the server is complete,
`nextcloud/Remove-MigratedUserData.ps1` can delete local files whose SHA-256 hash matches a file in the corresponding
Nextcloud destination folder, as well as empty local subfolders when the corresponding Nextcloud folder exists. Before
deletion, the user confirms that synchronization is complete and approves cleanup separately for each main folder.

| Script | Parameters and switches |
| --- | --- |
| `Copy-UserDataToNextcloud.ps1` | `-NextcloudPath <path>`, `-Folders <names>`, `-WhatIf`, `-Confirm`, `-EnglishOutput`. Copies only; source files are never deleted. |
| `Remove-MigratedUserData.ps1` | `-NextcloudPath <path>`, `-Folders <names>`, `-WhatIf`, `-Confirm`, `-EnglishOutput`. Deletes local files with matching SHA-256 hashes and empty subfolders when the corresponding Nextcloud folder exists. |

See the [Nextcloud tool guide](nextcloud/README.md) for details and examples.

## Testing

The GitHub Actions workflow runs `tests/Invoke-Tests.ps1` with Windows PowerShell 5.1 and PowerShell 7 for pull requests
targeting `main`. To run the same test suite locally, use `.\tests\Invoke-Tests.ps1` from the repository root; Pester 5
or later is required.

To run PSScriptAnalyzer locally, install it with
`Install-Module PSScriptAnalyzer -MinimumVersion 1.21.0 -Scope CurrentUser`, then run
`.\tests\Invoke-PSScriptAnalyzer.ps1`. The analyzer checks production PowerShell scripts outside `tests`; CI runs it
with PowerShell 7.

## License

The project is licensed under the [MIT License](LICENSE.md).
See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidance.
