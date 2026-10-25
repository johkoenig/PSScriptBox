# scriptbox

Small PowerShell utilities for everyday tasks. The tools currently documented here focus on PDF OCR, optimization, inspection, and backup cleanup.

## PDF tools

See the [PDF tools guide](pdf/README.md) for setup instructions, examples, dependencies, and the complete list of user-facing switches.

Available tools:

- `Setup-PdfProcessor.ps1` — checks and installs PDF-processing dependencies.
- `Invoke-PdfOptimization.ps1` — adds or refreshes OCR text, deskews pages, and optionally compresses PDFs.
- `Find-PdfsWithoutTextLayer.ps1` — reports PDFs with missing or partially missing text layers.
- `Clean-OriginalPdfs.ps1` — removes `_orig` backups only when the corresponding processed PDF exists.

Run scripts from PowerShell. The scripts select German console messages on a German Windows UI and English messages otherwise; `-EnglishOutput` forces English.

## PDF script parameters and switches

| Script | Parameters and switches |
| --- | --- |
| `Setup-PdfProcessor.ps1` | `-EnglishOutput`. Internal hidden parameters: `-ElevatedChild`, `-RuntimePythonPath`. |
| `Invoke-PdfOptimization.ps1` | `-InputPath <path>`, `-Language <codes>`, `-JpegQuality <1-100>`, `-GhostscriptDpi <50-1200>`, `-NoDeskew`, `-RotatePages`, `-NoGhostscript`, `-ReplaceOriginal`, `-RedoOcr`, `-EnglishOutput`. |
| `Find-PdfsWithoutTextLayer.ps1` | `-InputPath <path>`, `-EnglishOutput`. |
| `Clean-OriginalPdfs.ps1` | `-InputPath <folder>`, `-WhatIf`, `-Confirm` (use `-Confirm:$false` to suppress confirmation), `-EnglishOutput`. |

See the [PDF tools guide](pdf/README.md) for parameter behavior, examples, setup, dependencies, and safety notes.

## Documentation

- English: [README.md](README.md)
- German: [README.de.md](README.de.md)
- PDF tools (English): [pdf/README.md](pdf/README.md)
- PDF-Werkzeuge (Deutsch): [pdf/README.de.md](pdf/README.de.md)
