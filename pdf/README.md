# PDF PowerShell tools

> Deutsche Version: [README.de.md](README.de.md)

This folder contains PowerShell utilities for preparing and processing PDF files. Use Windows PowerShell 5.1 or PowerShell 7 from a regular user session unless a script explicitly requests elevation.

## Quick start

1. Open PowerShell in this folder.
2. Run the PDF script you need. Scripts that rely on external tools check them
   and print installation guidance if anything is missing.
3. Follow any instructions for missing Tesseract language data; scripts do not
   download `.traineddata` files.
4. Add OCR to scans and reduce PDF size as separate steps:

   ```powershell
   .\ConvertTo-SearchablePdf.ps1 -InputPath 'C:\PDFs'
   .\Optimize-PdfSize.ps1 -InputPath 'C:\PDFs'
   ```

PowerShell execution policy may require a policy-approved way to run local scripts. Do not weaken system policy globally just to run these tools.

## Dependency setup

Each PDF script that needs external executables or Python modules checks them
before processing files. Missing dependencies are reported individually with
Chocolatey commands, direct download links, or a pip command that names the
selected Python interpreter. Scripts do not install dependencies or request
administrator rights. Tesseract language data is not downloaded: the OCR
defaults are `deu+eng+fra+ita+spa`; `deu` and `eng` are required, and the other
languages are optional. The backup and restore scripts use built-in PowerShell
features and need no additional software.

## Scripts and switches

### `ConvertTo-SearchablePdf.ps1`

Adds OCR to scanned PDFs and corrects skewed or rotated pages. Digitally born PDFs are skipped using a heuristic based
on visible text and image resources; mixed or unusual documents may be classified imperfectly. Encrypted PDFs and
digitally signed PDFs cannot be processed and are reported as issues. OCRmyPDF image optimization is disabled so image
downsampling and JPEG compression remain the separate responsibility of `Optimize-PdfSize.ps1`. Existing OCR text is
preserved; Ghostscript renders
temporary page previews for Tesseract orientation detection, and pikepdf updates only page rotation metadata. This
avoids rerunning OCR or rasterizing pages that already have text. In partially OCRed scans, OCR is added only to pages
without text; deskew applies only to those pages. Ghostscript is optional for ordinary OCR but required for rotation
detection on pages that already have text. On success, the input is replaced; by default, a backup named
`<Name>_orig.pdf` is created. If that backup already exists, it is preserved and the input is replaced directly.

| Parameter / switch   | Description                                                                                                                                      |
|----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| `-InputPath <path>`  | PDF file or folder. If omitted, prompts for a path.                                                                                              |
| `-Language <codes>`  | `+`-separated Tesseract languages. Default: `deu+eng+fra+ita+spa`; `deu` and `eng` are required, and unavailable optional languages are removed. |
| `-NoDeskew`          | Disables deskew on pages that need OCR. Pages with existing text are not deskewed.                                                               |
| `-NoRotationOfPages` | Disables automatic rotation detection and correction. Rotation correction is enabled by default with confidence threshold `5`.                   |
| `-ReplaceOriginal`   | Replaces the input without creating a new `_orig` backup.                                                                                        |
| `-EnglishOutput`     | Forces English console output regardless of Windows UI language.                                                                                 |

Examples:

```powershell
.\ConvertTo-SearchablePdf.ps1
.\ConvertTo-SearchablePdf.ps1 -InputPath 'C:\PDFs' -NoRotationOfPages
.\ConvertTo-SearchablePdf.ps1 -InputPath 'C:\PDFs\Scan.pdf' -ReplaceOriginal
.\ConvertTo-SearchablePdf.ps1 -InputPath 'C:\PDFs' -Language 'deu+eng' -EnglishOutput
```

The result is a standard PDF, not PDF/A. Existing OCR text is not regenerated on later runs; rotation is changed only
when orientation detection identifies a correction above the confidence threshold. Routine skips and unchanged files
are counted in the summary but not listed individually; encrypted or signed PDFs appear in the issue list.

### `Optimize-PdfSize.ps1`

Reduces PDF size by downsampling color, grayscale, and monochrome images with Ghostscript. Color and grayscale images
are encoded as JPEG. Files smaller than 1 MB are skipped by default; the target is 300 DPI and JPEG quality 75.
Digitally signed and encrypted PDFs cannot be processed and are reported as issues. Digitally born PDFs are processed
as well as scans. The original is replaced only when the optimized PDF is smaller; by default, an `_orig.pdf` backup is
created, and existing backups are preserved. Files below the minimum size and files that produce no size reduction are
counted as skipped but are not listed individually in the summary. For folder input, all PDFs are discovered first and
only files meeting the minimum size are passed to the processing loop.

| Parameter / switch     | Description                                                                                                                     |
|------------------------|---------------------------------------------------------------------------------------------------------------------------------|
| `-InputPath <path>`    | PDF file or folder. If omitted, prompts for a path.                                                                             |
| `-Dpi <50-1200>`       | Target resolution for image downsampling. Default: `300`.                                                                       |
| `-JpegQuality <1-100>` | JPEG quality for downsampled color and grayscale images. Default: `75`.                                                         |
| `-MinFileSize <bytes>` | Minimum original file size to process. Default: `1MB`; use `0` to disable. PowerShell size literals such as `2MB` are accepted. |
| `-ReplaceOriginal`     | Replaces the input without creating a new `_orig` backup.                                                                       |
| `-EnglishOutput`       | Forces English console output regardless of Windows UI language.                                                                |

Examples:

```powershell
.\Optimize-PdfSize.ps1
.\Optimize-PdfSize.ps1 -InputPath 'C:\PDFs' -Dpi 200 -JpegQuality 65 -MinFileSize 2MB
.\Optimize-PdfSize.ps1 -InputPath 'C:\PDFs\Document.pdf' -ReplaceOriginal
```

### `Find-PdfsWithoutTextLayer.ps1`

Reports PDFs with no text operators and PDFs where only some pages contain text operators. It does not assess OCR quality and does not modify files.

| Parameter / switch | Description |
| --- | --- |
| `-InputPath <path>` | PDF file or folder to inspect recursively. If omitted, prompts for a path. |
| `-EnglishOutput` | Forces English console output regardless of Windows UI language. |

Examples:

```powershell
.\Find-PdfsWithoutTextLayer.ps1 -InputPath 'C:\PDFs'
.\Find-PdfsWithoutTextLayer.ps1 -InputPath 'C:\PDFs\Scan.pdf' -EnglishOutput
```

### `Remove-PdfBackups.ps1`

Finds `_orig.pdf` backups for which the corresponding processed PDF exists in the same folder. Each deletion is subject to PowerShell's confirmation behavior.

| Parameter / switch    | Description                                                                      |
|-----------------------|----------------------------------------------------------------------------------|
| `-InputPath <folder>` | Folder to search recursively. If omitted, prompts for a path.                    |
| `-WhatIf`             | Lists planned deletions without deleting files.                                  |
| `-Confirm`            | Prompts before each deletion. Deletion proceeds without confirmation by default. |
| `-EnglishOutput`      | Forces English console output regardless of Windows UI language.                 |

Examples:

```powershell
.\Remove-PdfBackups.ps1 -InputPath 'C:\PDFs' -WhatIf
.\Remove-PdfBackups.ps1 -InputPath 'C:\PDFs'
.\Remove-PdfBackups.ps1 -InputPath 'C:\PDFs' -Confirm
.\Remove-PdfBackups.ps1 -InputPath 'C:\PDFs' -EnglishOutput
```

### `Restore-PdfOriginals.ps1`

Finds `_orig.pdf` backups whose corresponding processed PDFs exist in the same folder. For each approved pair, it
atomically replaces the processed PDF with the original backup, removing the processed file and consuming the `_orig`
backup. Restoration proceeds without confirmation by default; use `-Confirm` to opt in to per-file prompts.

| Parameter / switch    | Description                                                               |
|-----------------------|---------------------------------------------------------------------------|
| `-InputPath <folder>` | Folder to search recursively. If omitted, prompts for a path.             |
| `-WhatIf`             | Lists planned restorations without changing files.                        |
| `-Confirm`            | Prompts before each restoration. No confirmation is requested by default. |
| `-EnglishOutput`      | Forces English console output regardless of Windows UI language.          |

Examples:

```powershell
.\Restore-PdfOriginals.ps1 -InputPath 'C:\PDFs' -WhatIf
.\Restore-PdfOriginals.ps1 -InputPath 'C:\PDFs'
.\Restore-PdfOriginals.ps1 -InputPath 'C:\PDFs' -Confirm -EnglishOutput
```

## Shared PowerShell parameters

Scripts also support PowerShell common parameters where applicable, including `-Verbose`, `-Debug`, `-ErrorAction`, and
`-WarningAction`. `-WhatIf` and `-Confirm` are supported by `Remove-PdfBackups.ps1` and `Restore-PdfOriginals.ps1`
through `SupportsShouldProcess`.

## Safety and behavior

- Both optimization scripts use temporary files beside the input and clean them up after processing.
- No persistent state or marker file is created beside a PDF. Temporary processing files are removed after the run.
- OCR classification is stateless and uses visible text and scanned-image evidence. It is best-effort and may
  misclassify mixed or unusual PDFs. Existing OCR text is preserved; page rotation is corrected by updating PDF page
  metadata, and OCR is added only to pages without text.
- The OCR script accepts changed results even when they are larger than the original. The size script replaces a PDF
  only when Ghostscript produces a smaller result.
- Existing `_orig` backups are preserved.
- `Remove-PdfBackups.ps1` deletes only backups whose corresponding processed PDF exists.
- `Restore-PdfOriginals.ps1` restores only matching backup/processed pairs; a successful restore replaces the processed
  PDF and removes the `_orig` backup.
- Do not use these tools on files that must remain byte-identical, such as digitally signed PDFs.
- The project is licensed under the [MIT License](../LICENSE.md).
- Contribution guidance is in [CONTRIBUTING.md](../CONTRIBUTING.md).
