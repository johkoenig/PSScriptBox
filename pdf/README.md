# PDF PowerShell tools

This folder contains PowerShell utilities for preparing and processing PDF files. Use Windows PowerShell 5.1 or PowerShell 7 from a regular user session unless a script explicitly requests elevation.

## Quick start

1. Open PowerShell in this folder.
2. Run the dependency setup:

   ```powershell
   .\Initialize-PdfProcessor.ps1
   ```

3. Follow any instructions for missing Tesseract language data. The setup script does not download `.traineddata` files.
4. Process PDFs, for example:

   ```powershell
   .\Optimize-ScannedPdfs.ps1 -InputPath 'C:\PDFs'
   ```

PowerShell execution policy may require a policy-approved way to run local scripts. Do not weaken system policy globally just to run these tools.

## Dependency setup

`Initialize-PdfProcessor.ps1` requires Chocolatey to be installed separately. It checks Chocolatey, Python, OCRmyPDF, pikepdf, Tesseract, and Ghostscript individually.

- Missing machine-wide programs are installed through Chocolatey.
- The setup prefers a working Python interpreter in the current user's profile; otherwise it selects a working machine-wide interpreter.
- `py.exe` is only used to discover a concrete `python.exe` path. Scripts then invoke that interpreter directly.
- Missing Python packages are installed into the selected interpreter. A machine-wide interpreter requires administrator privileges.
- Before opening the UAC prompt, setup lists the planned operations and waits for Enter. Any non-empty response cancels.
- Tesseract language data is inspected but never downloaded. The OCR defaults are `deu+eng+fra+ita+spa+equ`; `deu` and `eng` are required. The other models, including `equ` for equation recognition, are optional.

## Scripts and switches

### `Initialize-PdfProcessor.ps1`

Checks dependencies, installs missing software, and reports missing Tesseract language data.

| Switch | Description |
| --- | --- |
| `-EnglishOutput` | Forces English console output regardless of Windows UI language. |

The hidden `-ElevatedChild` and `-RuntimePythonPath` parameters are internal implementation details and are not intended for direct use.

Examples:

```powershell
.\Initialize-PdfProcessor.ps1
.\Initialize-PdfProcessor.ps1 -EnglishOutput
```

### `Optimize-ScannedPdfs.ps1`

Processes scanned PDFs in one file or a folder tree. Digitally born PDFs are skipped by default. The script uses PDF text visibility and image-resource evidence as a heuristic; mixed and unusual documents may be classified imperfectly. Use `-ProcessDigitallyBornPdfs` to process digitally born PDFs anyway. OCRmyPDF adds a text layer to pages that need it, deskews scans, and detects rotated pages by default. The input is replaced after successful processing; by default, a backup named `<Name>_orig.pdf` is created. If that backup already exists, it is preserved and the input is replaced without overwriting the backup.

Scanned PDFs that already contain OCR text are reprocessed by default so deskew and rotation correction can run. OCRmyPDF uses `--force-ocr` for those files, regenerating the OCR layer and rasterizing page content; this can alter vector content and can change the PDF on repeated runs. Use `-NoDeskew` or `-NoRotationOfPages` to disable the corresponding correction.

| Parameter / switch | Description |
| --- | --- |
| `-InputPath <path>` | PDF file or folder. If omitted, prompts for a path. |
| `-Language <codes>` | `+`-separated Tesseract languages. Default: `deu+eng+fra+ita+spa+equ`; `deu` and `eng` are required. `equ` is Tesseract's optional equation-recognition model, not an OCRmyPDF subcommand. |
| `-JpegQuality <1-100>` | JPEG quality for embedded images. Default: `75`. |
| `-GhostscriptDpi <50-1200>` | Enables Ghostscript downsampling at the specified DPI. Default: disabled (`0`). |
| `-NoDeskew` | Disables the default deskew operation. |
| `-NoRotationOfPages` | Disables automatic rotation detection and correction. Rotation correction is enabled by default, using confidence threshold `5`. |
| `-ProcessDigitallyBornPdfs` | Processes PDFs classified as digitally born; these are skipped by default. |
| `-NoGhostscript` | Disables the optional Ghostscript stage. |
| `-ReplaceOriginal` | Replaces the input without creating a new `_orig` backup. |
| `-ForceReprocess` | Explicitly reprocesses PDFs with existing text when digitally born PDFs are enabled. Scanned PDFs with existing OCR are already reprocessed by default. |
| `-EnglishOutput` | Forces English console output regardless of Windows UI language. |

Examples:

```powershell
.\Optimize-ScannedPdfs.ps1
.\Optimize-ScannedPdfs.ps1 -InputPath 'C:\PDFs' -GhostscriptDpi 150
.\Optimize-ScannedPdfs.ps1 -InputPath 'C:\PDFs' -NoRotationOfPages
.\Optimize-ScannedPdfs.ps1 -InputPath 'C:\PDFs\Scan.pdf' -ReplaceOriginal
.\Optimize-ScannedPdfs.ps1 -InputPath 'C:\PDFs' -ProcessDigitallyBornPdfs
.\Optimize-ScannedPdfs.ps1 -InputPath 'C:\PDFs' -Language 'deu+eng' -EnglishOutput
```

Digitally born PDFs are skipped by default, without rewriting them. Scanned PDFs with existing text are automatically processed with OCRmyPDF force mode so deskew and rotation correction can run; OCR is regenerated and page content is rasterized. `-ProcessDigitallyBornPdfs` opts into processing digitally born PDFs, and `-ForceReprocess` can explicitly rebuild their existing text layer. Repeated processing may change the output and is not guaranteed to be idempotent. Signed PDFs and encrypted PDFs that cannot be opened without a password are skipped. The result is a standard PDF, not PDF/A. Ghostscript runs only when `-GhostscriptDpi` is specified.

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

### `Clear-OriginalPdfBackups.ps1`

Finds `_orig.pdf` backups for which the corresponding processed PDF exists in the same folder. Each deletion is subject to PowerShell's confirmation behavior.

| Parameter / switch | Description |
| --- | --- |
| `-InputPath <folder>` | Folder to search recursively. If omitted, prompts for a path. |
| `-WhatIf` | Lists planned deletions without deleting files. |
| `-Confirm` | Prompts before each deletion. This is enabled by default because deletion is a high-impact action; `-Confirm:$false` suppresses prompts. |
| `-EnglishOutput` | Forces English console output regardless of Windows UI language. |

Examples:

```powershell
.\Clear-OriginalPdfBackups.ps1 -InputPath 'C:\PDFs' -WhatIf
.\Clear-OriginalPdfBackups.ps1 -InputPath 'C:\PDFs' -Confirm:$false
.\Clear-OriginalPdfBackups.ps1 -InputPath 'C:\PDFs' -EnglishOutput
```

## Shared PowerShell parameters

Scripts also support PowerShell common parameters where applicable, including `-Verbose`, `-Debug`, `-ErrorAction`, and `-WarningAction`. `-WhatIf` and `-Confirm` are supported by `Clear-OriginalPdfBackups.ps1` through `SupportsShouldProcess`.

## Safety and behavior

- `Optimize-ScannedPdfs.ps1` uses temporary files beside the input and cleans them up after processing.
- No persistent state or marker file is created beside a PDF. Temporary processing files are removed after the run.
- Classification is stateless and uses visible text and scanned-image evidence. It is best-effort and may misclassify mixed or unusual PDFs. Existing OCR on scanned PDFs is regenerated to enable page corrections; this also rasterizes page content.
- A PDF is considered successfully changed only when processing succeeds and the result hash differs from the original. Larger results can still be valid.
- Existing `_orig` backups are preserved.
- `Clear-OriginalPdfBackups.ps1` deletes only backups whose corresponding processed PDF exists.
- Do not use these tools on files that must remain byte-identical, such as digitally signed PDFs.
- The project is licensed under the [MIT License](../LICENSE.md).
- Contribution guidance is in [CONTRIBUTING.md](../CONTRIBUTING.md).

## Related documentation

- Repository overview (English): [../README.md](../README.md)
- Repository overview (German): [../README.de.md](../README.de.md)
- PDF tools (German): [README.de.md](README.de.md)
