# PDF PowerShell tools

This folder contains PowerShell utilities for preparing and processing PDF files. Use Windows PowerShell 5.1 or PowerShell 7 from a regular user session unless a script explicitly requests elevation.

## Quick start

1. Open PowerShell in this folder.
2. Run the dependency setup:

   ```powershell
   .\Setup-PdfProcessor.ps1
   ```

3. Follow any instructions for missing Tesseract language data. The setup script does not download `.traineddata` files.
4. Process PDFs, for example:

   ```powershell
   .\Invoke-PdfOptimization.ps1 -InputPath 'C:\PDFs'
   ```

PowerShell execution policy may require a policy-approved way to run local scripts. Do not weaken system policy globally just to run these tools.

## Dependency setup

`Setup-PdfProcessor.ps1` requires Chocolatey to be installed separately. It checks Chocolatey, Python, OCRmyPDF, pikepdf, Tesseract, and Ghostscript individually.

- Missing machine-wide programs are installed through Chocolatey.
- The setup prefers a working Python interpreter in the current user's profile; otherwise it selects a working machine-wide interpreter.
- `py.exe` is only used to discover a concrete `python.exe` path. Scripts then invoke that interpreter directly.
- Missing Python packages are installed into the selected interpreter. A machine-wide interpreter requires administrator privileges.
- Before opening the UAC prompt, setup lists the planned operations and waits for Enter. Any non-empty response cancels.
- Tesseract language data is inspected but never downloaded. The OCR defaults are `deu+eng+fra+ita+spa`; `deu` and `eng` are required.

## Scripts and switches

### `Setup-PdfProcessor.ps1`

Checks dependencies, installs missing software, and reports missing Tesseract language data.

| Switch | Description |
| --- | --- |
| `-EnglishOutput` | Forces English console output regardless of Windows UI language. |

The hidden `-ElevatedChild` and `-RuntimePythonPath` parameters are internal implementation details and are not intended for direct use.

Examples:

```powershell
.\Setup-PdfProcessor.ps1
.\Setup-PdfProcessor.ps1 -EnglishOutput
```

### `Invoke-PdfOptimization.ps1`

Processes one PDF or all PDFs in a folder tree. OCRmyPDF adds a text layer when necessary and deskews scans. The input is replaced after successful processing; by default, a backup named `<Name>_orig.pdf` is created. If that backup already exists, it is preserved and the input is replaced without overwriting the backup.

| Parameter / switch | Description |
| --- | --- |
| `-InputPath <path>` | PDF file or folder. If omitted, prompts for a path. |
| `-Language <codes>` | `+`-separated Tesseract languages. Default: `deu+eng+fra+ita+spa`; `deu` and `eng` are required. |
| `-JpegQuality <1-100>` | JPEG quality for embedded images. Default: `75`. |
| `-GhostscriptDpi <50-1200>` | Enables Ghostscript downsampling at the specified DPI. Default: disabled (`0`). |
| `-NoDeskew` | Disables the default deskew operation. |
| `-RotatePages` | Enables automatic rotation detection and correction. Disabled by default. |
| `-NoGhostscript` | Disables the optional Ghostscript stage. |
| `-ReplaceOriginal` | Replaces the input without creating a new `_orig` backup. |
| `-RedoOcr` | Reprocesses existing OCR text with OCRmyPDF `--redo-ocr`; it does not rasterize the entire page. |
| `-ForceReprocess` | Overrides the default skip for PDFs that already have a complete text layer. Repeated forced runs can change the PDF again. |
| `-EnglishOutput` | Forces English console output regardless of Windows UI language. |

Examples:

```powershell
.\Invoke-PdfOptimization.ps1
.\Invoke-PdfOptimization.ps1 -InputPath 'C:\PDFs' -RotatePages -GhostscriptDpi 150
.\Invoke-PdfOptimization.ps1 -InputPath 'C:\PDFs\Scan.pdf' -RedoOcr -ReplaceOriginal
.\Invoke-PdfOptimization.ps1 -InputPath 'C:\PDFs' -ForceReprocess
.\Invoke-PdfOptimization.ps1 -InputPath 'C:\PDFs' -Language 'deu+eng' -EnglishOutput
```

PDFs with a complete text layer are skipped by default, without rewriting them. This avoids repeat processing without storing a persistent sidecar file. Use `-ForceReprocess` to run optimization anyway, or `-RedoOcr` to rebuild existing OCR text. Those explicit options can modify the PDF on repeated runs and are not guaranteed to be idempotent. Signed PDFs and encrypted PDFs that cannot be opened without a password are skipped. The result is a standard PDF, not PDF/A. Ghostscript runs only when `-GhostscriptDpi` is specified.

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

### `Clean-OriginalPdfs.ps1`

Finds `_orig.pdf` backups for which the corresponding processed PDF exists in the same folder. Each deletion is subject to PowerShell's confirmation behavior.

| Parameter / switch | Description |
| --- | --- |
| `-InputPath <folder>` | Folder to search recursively. If omitted, prompts for a path. |
| `-WhatIf` | Lists planned deletions without deleting files. |
| `-Confirm` | Prompts before each deletion. This is enabled by default because deletion is a high-impact action; `-Confirm:$false` suppresses prompts. |
| `-EnglishOutput` | Forces English console output regardless of Windows UI language. |

Examples:

```powershell
.\Clean-OriginalPdfs.ps1 -InputPath 'C:\PDFs' -WhatIf
.\Clean-OriginalPdfs.ps1 -InputPath 'C:\PDFs' -Confirm:$false
.\Clean-OriginalPdfs.ps1 -InputPath 'C:\PDFs' -EnglishOutput
```

## Shared PowerShell parameters

Scripts also support PowerShell common parameters where applicable, including `-Verbose`, `-Debug`, `-ErrorAction`, and `-WarningAction`. `-WhatIf` and `-Confirm` are supported by `Clean-OriginalPdfs.ps1` through `SupportsShouldProcess`.

## Safety and behavior

- `Invoke-PdfOptimization.ps1` uses temporary files beside the input and cleans them up after processing.
- No persistent state or marker file is created beside a PDF. Temporary processing files are removed after the run.
- Complete text layers are used as a stateless indication that OCR has already been applied; such PDFs are skipped unless `-ForceReprocess` or `-RedoOcr` is used. This is best-effort idempotency: it cannot tell whether a digitally born PDF needs image optimization.
- A PDF is considered successfully changed only when processing succeeds and the result hash differs from the original. Larger results can still be valid.
- Existing `_orig` backups are preserved.
- `Clean-OriginalPdfs.ps1` deletes only backups whose corresponding processed PDF exists.
- Do not use these tools on files that must remain byte-identical, such as digitally signed PDFs.
- The project is licensed under the [MIT License](../LICENSE.md).

## Related documentation

- Repository overview (English): [../README.md](../README.md)
- Repository overview (German): [../README.de.md](../README.de.md)
- PDF tools (German): [README.de.md](README.de.md)
