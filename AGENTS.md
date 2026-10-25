# AGENTS.md

Repository guidance, especially for PowerShell scripts.

## Language, comments, and help
- Write all source-code comments and documentation in English. Keep technical terms and Tesseract language codes (for example, `deu` and `eng`) in English.
- Console messages must be localized: use German when the Windows UI culture is German and English otherwise. Every script must provide an `-EnglishOutput` switch to force English.
- Keep translations out of executable logic. Use shared message catalogs under `pdf/l10n/<culture>/Messages.psd1` and a small, documented lookup helper. English source strings are the fallback; add German translations to the German catalog.
- Every script starts with comment-based help containing `.SYNOPSIS`, `.DESCRIPTION`, at least one `.EXAMPLE`, and `.NOTES` listing dependencies.
- Keep user-facing documentation in both top-level `README.md` / `README.de.md` and each tool folder's `README.md` / `README.de.md`. Update all applicable README files whenever script content, behavior, parameters, or user workflows change; keep the English and German versions consistent.
- PowerShell script documentation (comment-based help, parameter descriptions, examples, and notes) must remain complete and current in English only. Update it whenever script behavior or interface changes.
- User-facing English and German READMEs at the repository root and in each tool folder must remain synchronized with script behavior, parameters, and workflows.
- Every PowerShell script or module file (`.ps1`, `.psm1`) has a filename in the approved `Verb-Noun` form, whether user-facing or internal. Check the verb with `Get-Verb`; use a specific noun that clearly describes the file's action or responsibility. Update every caller, example, and documentation reference when a file is renamed.
- PowerShell helper scripts or modules that are not intended to be run directly belong in an `internal` or other clearly named subfolder, not beside user-facing scripts. Their filenames must also follow the approved `Verb-Noun` form, and callers must resolve them with paths relative to `$PSScriptRoot`.
- Every PowerShell function has a complete comment-based-help block immediately before its definition or at the start of its script block. Include `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` for every parameter, and `.OUTPUTS`. Add `.EXAMPLE` and `.NOTES` when they clarify usage or dependencies.
- Every PowerShell function and user-defined method follows the `ApprovedVerb-Noun` pattern. Check every prefix against `Get-Verb`; do not assume a familiar English verb is approved. Use a specific noun, and update callers and tests whenever a function or method is renamed.
- Comment on non-obvious decisions and explain why. Do not add comments that merely restate obvious code; use short section headings to structure the main script.

## PowerShell style
- Set `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` near the start of every script.
- Use `[CmdletBinding()]` on scripts and functions; mark required parameters with `[Parameter(Mandatory)]`.
- Report user-facing status and errors through `Write-Host`, `Write-Warning`, or `Write-Error`, not `Write-Output`.
- Use `-LiteralPath` and `Join-Path` consistently. Normalize user input with `Trim()` and `ExpandEnvironmentVariables()` before use.
- Start external console programs with redirected streams and read asynchronously so errors are not mistaken for PowerShell terminating errors and large output cannot block a pipe. Exception: run OCRmyPDF without stream redirection so its progress bar is displayed live.
- Save PowerShell scripts with a UTF-8 BOM (U+FEFF). Windows PowerShell 5.1 otherwise interprets non-ASCII text as ANSI.
- License the project and its files under the MIT License. Keep the standard license text in the root `LICENSE.md` and add an SPDX-License-Identifier: MIT header and the project copyright notice to every PowerShell script and PowerShell data file. Place headers after the required script help block.

## Dependencies and installation
- Processing and inspection scripts do not install software and should not require administrator rights to run. `pdf/Initialize-PdfProcessor.ps1` is the exception: it checks dependency state first and elevates only when installation is required. Chocolatey is a prerequisite and is never installed by the script.
- All PDF scripts dot-source `pdf/internal/Get-PdfPythonRuntime.ps1` to choose a working `python.exe` consistently. Prefer a Python interpreter in the current user's profile; use `py.exe` only to discover a concrete interpreter path when direct `python.exe` discovery fails. Invoke the resolved `python.exe` directly for checks and processing.
- The setup script validates Chocolatey, Python, OCRmyPDF, pikepdf, Tesseract, and Ghostscript individually. Chocolatey installs missing system dependencies machine-wide. Before any UAC prompt, show the exact planned operations and wait for Enter (any non-empty response cancels). Install Python packages into the selected interpreter: user-scoped Python is installed without elevation; machine-wide Python is installed from the elevated child process. Do not use `pip --user`, which can install into a different site than the selected interpreter. It checks Tesseract language data but never downloads `.traineddata` files; it instructs the user to download any missing languages.
- Check all required dependencies together and report missing dependencies with installation instructions.
- Optional tools such as Ghostscript must not block a run when unavailable. Do not use `jbig2`.

## Files and data
- Scripts should be idempotent where practical. Prefer stateless detection over persistent state files, and never add persistent files beside user data unless the user approves them. Document limits to idempotency and any explicit force/bypass options; users may knowingly bypass idempotency with such options.
- Never hardcode or store personal data in source files (except author tags). Discover user profile paths, account names, email addresses, and other environment-specific values dynamically. Scripts must work on Windows with local, Active Directory, and Microsoft online accounts.
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
- PDFs with a complete text layer are skipped entirely by default to avoid repeat rewriting without a persistent marker. `-ForceReprocess` overrides this safeguard; `-RedoOcr` selects `--redo-ocr` to rebuild existing OCR text without rasterizing all visible text and vector graphics. Repeated use of either explicit override may modify a PDF again. Digitally signed and password-protected PDFs that cannot be opened without a password are skipped.
- `pdf/Clear-OriginalPdfBackups.ps1` removes `_orig` PDF backups only when the corresponding processed PDF exists beside them. `-WhatIf` previews deletion.
- `pdf/Find-PdfsWithoutTextLayer.ps1` recursively finds PDFs without text operators and lists partially missing text layers separately. It requires Python and `pikepdf` and does not modify files.
- OCRmyPDF's raw output, including progress bars and internal module names such as `_pipeline.py`, is shown unchanged in the console.

## Quality assurance before committing
- When possible, test script changes with a sample PDF in both parameter and interactive modes.
- Review `git diff` before committing. Do not commit local test PDFs, temporary files, or binary artifacts.
- Keep commit messages short and factual. Automatically generated commit messages must include exactly one `Signed-off-by` trailer for the user and exactly one `Co-authored-by` trailer for the AI engine used. Use the user's confirmed name and email for the sign-off and the active AI engine's configured name and email for co-authorship; do not invent or assume either identity. Place both trailers at the end of the commit message.
