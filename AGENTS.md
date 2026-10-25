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
- Include a `Contributors` section in every code file, listing the contributors and contact details explicitly approved for attribution.

## Dependencies and installation
- Scripts that only process or inspect user files must not install software and should not require administrator rights.
- Dependency-installation scripts must inspect the current dependency state first and elevate only when required. Before any UAC prompt, show the exact planned operations and require explicit confirmation. Install packages into the selected runtime; do not use user-scoped package options that can target a different interpreter.
- Reuse shared internal helpers for runtime discovery and other behavior used by multiple scripts. Resolve helper paths relative to `$PSScriptRoot`, prefer a working interpreter in the current user's profile, and invoke the resolved executable directly. Use a launcher only to discover a concrete runtime path when direct discovery fails.
- Check all required dependencies together and report missing dependencies with installation instructions.
- Optional tools must not block a run when unavailable. Report their absence and continue with the supported reduced behavior.

## Files and data
- Scripts should be idempotent where practical. Prefer stateless detection over persistent state files, and never add persistent files beside user data unless the user approves them. Document limits to idempotency and any explicit force/bypass options; users may knowingly bypass idempotency with such options.
- Never hardcode or store personal data in source files (except author tags). Discover user profile paths, account names, email addresses, and other environment-specific values dynamically. Scripts must work on Windows with local, Active Directory, and Microsoft online accounts.
- Preserve user inputs unless the documented operation explicitly modifies or deletes them. For multi-stage document processing, do not replace an intermediate result with a downstream optimization unless the result improves according to the operation's stated acceptance criteria.
- Keep temporary files on the same volume as their inputs when atomic replacement requires it, and reliably remove them in a `finally` block.
- Do not add secrets, tokens, API keys, or personal data to the repository.

## Quality assurance before committing
- Test relevant code paths with representative, non-confidential fixtures when possible. Do not commit personal documents, local test data, temporary files, or generated binary artifacts.
- Review `git diff` before committing and verify documentation and code changes are consistent.
- Keep commit messages short and factual. Automatically generated commit messages must include exactly one `Signed-off-by` trailer for the user and exactly one `Co-authored-by` trailer for the AI engine used. Use the user's confirmed name and email for the sign-off and the active AI engine's configured name and email for co-authorship; do not invent or assume either identity. Place both trailers at the end of the commit message.
