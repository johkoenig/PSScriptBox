# AGENTS.md

Repository guidance, especially for PowerShell scripts.

## Language, comments, and help
- Write all source-code comments and documentation in English. Keep technical terms and Tesseract language codes (for example, `deu` and `eng`) in English.
- Console messages must be localized: use German when the Windows UI culture is German and English otherwise. Every script must provide an `-EnglishOutput` switch to force English.
- Keep translations out of executable logic. Use shared message catalogs under `pdf/Localization/<culture>/Messages.psd1` and a small, documented lookup helper. English source strings are the fallback; add German translations to the German catalog.
- Every script starts with comment-based help containing `.SYNOPSIS`, `.DESCRIPTION`, at least one `.EXAMPLE`, and `.NOTES` listing dependencies.
- Every PowerShell function has a complete comment-based-help block immediately before its definition or at the start of its script block. Include `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` for every parameter, and `.OUTPUTS`. Add `.EXAMPLE` and `.NOTES` when they clarify usage or dependencies.
- Every PowerShell function follows the `ApprovedVerb-Noun` pattern. Check verbs with `Get-Verb`; update callers and tests when renaming functions.
- Comment on non-obvious decisions and explain why. Do not add comments that merely restate obvious code; use short section headings to structure the main script.

## PowerShell style
- Set `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` near the start of every script.
- Use `[CmdletBinding()]` on scripts and functions; mark required parameters with `[Parameter(Mandatory)]`.
- Report user-facing status and errors through `Write-Host`, `Write-Warning`, or `Write-Error`, not `Write-Output`.
- Use `-LiteralPath` and `Join-Path` consistently. Normalize user input with `Trim()` and `ExpandEnvironmentVariables()` before use.
- Start external console programs with redirected streams and read asynchronously so errors are not mistaken for PowerShell terminating errors and large output cannot block a pipe. Exception: run OCRmyPDF without stream redirection so its progress bar is displayed live.
- Save PowerShell scripts with a UTF-8 BOM (U+FEFF). Windows PowerShell 5.1 otherwise interprets non-ASCII text as ANSI.

## Dependencies and installation
- Scripts do not install software and should not require administrator rights to run.
- Check all required dependencies together and report missing dependencies with installation instructions.
- Optional tools such as Ghostscript must not block a run when unavailable. Do not use `jbig2`.

## Files and data
- By default, save the input PDF after successful processing as `<Name>_orig.pdf`. `-ReplaceOriginal` replaces the input without a backup.
- Treat processing as failed only when OCRmyPDF fails or the final result has the same SHA-256 hash as the original. A larger but changed result is successful.
- A downstream optimization stage may replace its intermediate result only when it makes the file smaller.
- Place temporary files beside the input and reliably remove them in a `finally` block.
- Do not add secrets, tokens, API keys, or personal data to the repository.

## `pdf/Invoke-PdfOptimization.ps1`
- The default OCR language sequence is `deu+eng+fra+ita+spa` in that order. `-Language` can override it; do not prompt interactively for languages.
- `deu` and `eng` are required. If either is missing, stop and provide the tessdata download instructions. Other missing languages are removed from the selected sequence and reported without stopping.
- Deskew is enabled by default with `--deskew` and can be disabled with `-NoDeskew`. Page rotation is disabled by default; `-RotatePages` enables correction with an OCRmyPDF confidence threshold of 5.
- OCRmyPDF outputs a standard PDF using `--output-type pdf`; do not switch to PDF/A.
- Do not pass `--image-dpi`: OCRmyPDF ignores it for PDF inputs. Image resolution is controlled by the optional Ghostscript stage when `-GhostscriptDpi` is specified.
- Use `--optimize 1` rather than `--optimize 3`; level 3 can warn about the intentionally unavailable `jbig2` encoder.
- Ghostscript is an optional second optimization stage. It uses explicit downsampling parameters, JPEG quality 75, and sRGB conversion, and runs only when `-GhostscriptDpi` is greater than zero and Ghostscript is available. `-NoGhostscript` disables it. Do not use qpdf.
- PDFs with a complete text layer use OCRmyPDF's `--skip-text` mode by default; optimization still runs. `-ForceOcrRescan` selects `--force-ocr`. Digitally signed and password-protected PDFs that cannot be opened without a password are skipped.
- `pdf/Clean-OriginalPdfs.ps1` removes `_orig` PDF backups only when the corresponding processed PDF exists beside them. `-WhatIf` previews deletion.
- `pdf/Find-PdfsWithoutTextLayer.ps1` recursively finds PDFs without text operators and lists partially missing text layers separately. It requires Python and `pikepdf` and does not modify files.
- OCRmyPDF's raw output, including progress bars and internal module names such as `_pipeline.py`, is shown unchanged in the console.

## Quality assurance before committing
- When possible, test script changes with a sample PDF in both parameter and interactive modes.
- Review `git diff` before committing. Do not commit local test PDFs, temporary files, or binary artifacts.
- Keep commit messages short and factual.
