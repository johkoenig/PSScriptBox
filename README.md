# scriptbox

Small PowerShell utilities for everyday tasks, including PDF processing and Git configuration.

## PDF tools

See the [PDF tools guide](pdf/README.md) for setup instructions, examples, dependencies, and the complete list of user-facing switches.

Available tools:

- `Initialize-PdfProcessor.ps1` — checks and installs PDF-processing dependencies.
- `Optimize-ScannedPdfs.ps1` — processes scanned PDFs, adds OCR where needed, corrects page orientation, and optionally compresses PDFs.
- `Find-PdfsWithoutTextLayer.ps1` — reports PDFs with missing or partially missing text layers.
- `Clear-OriginalPdfBackups.ps1` — removes `_orig` backups only when the corresponding processed PDF exists.

Run scripts from PowerShell. The scripts select German console messages on a German Windows UI and English messages otherwise; `-EnglishOutput` forces English.

## Git configuration

`git/Initialize-GitConfiguration.ps1` sets the Git author identity (local or global) by offering discovered names and emails (existing Git settings, Active Directory / Windows account data, Microsoft account) or a custom value, and confirms recommended standard settings one by one. Existing values are the defaults and nothing is stored in the script. See the [Git tool guide](git/README.md) for parameters and examples.

## PDF script parameters and switches

| Script | Parameters and switches |
| --- | --- |
| `Initialize-PdfProcessor.ps1` | `-EnglishOutput`. Internal hidden parameters: `-ElevatedChild`, `-RuntimePythonPath`. |
| `Optimize-ScannedPdfs.ps1` | `-InputPath <path>`, `-Language <codes>`, `-JpegQuality <1-100>`, `-GhostscriptDpi <50-1200>`, `-NoDeskew`, `-NoRotationOfPages`, `-ProcessDigitallyBornPdfs`, `-NoGhostscript`, `-ReplaceOriginal`, `-ForceReprocess`, `-EnglishOutput`. |
| `Find-PdfsWithoutTextLayer.ps1` | `-InputPath <path>`, `-EnglishOutput`. |
| `Clear-OriginalPdfBackups.ps1` | `-InputPath <folder>`, `-WhatIf`, `-Confirm` (use `-Confirm:$false` to suppress confirmation), `-EnglishOutput`. |

See the [PDF tools guide](pdf/README.md) for parameter behavior, examples, setup, dependencies, and safety notes.

## Other tool parameters and switches

| Script | Parameters and switches |
| --- | --- |
| `Initialize-GitConfiguration.ps1` | `-RepositoryPath <path>`, `-Scope <Local\|Global>`, `-Name <name>`, `-Email <address>`, `-EnglishOutput`. |

Scanned-PDF processing uses best-effort, stateless classification: digitally born PDFs are skipped by default, and no persistent marker is written beside them. Scanned PDFs with existing OCR are reprocessed automatically so deskew and rotation correction can run; OCR is regenerated and page content is rasterized. `-ProcessDigitallyBornPdfs` opts into processing digitally born PDFs. Classification is heuristic and may not identify mixed or unusual PDFs correctly.

The project is licensed under the [MIT License](LICENSE.md).
See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidance.

## Documentation

- English: [README.md](README.md)
- German: [README.de.md](README.de.md)
- PDF tools (English): [pdf/README.md](pdf/README.md)
- PDF-Werkzeuge (Deutsch): [pdf/README.de.md](pdf/README.de.md)
- Git tool (English): [git/README.md](git/README.md)
- Git-Werkzeug (Deutsch): [git/README.de.md](git/README.de.md)
