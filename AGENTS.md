# AGENTS.md

Repository guidance, especially for PowerShell scripts.

## Language, comments, and help
- All code is English only: identifiers, variables, parameters, source-code comments, comment-based help, and code documentation. Keep technical terms and Tesseract language codes (for example, `deu` and `eng`) in English.
- German text appears only in the German message catalog (`l10n/de-DE/Messages.psd1`) and in console output or input prompts the user sees. Never put German text into code, comments, or help.
- Console messages must be localized: use German when the Windows UI culture is German and English otherwise. Every script must provide an `-EnglishOutput` switch to force English.
- Keep translations out of executable logic. Use a message catalog under the relevant tool folder's `l10n/<culture>/Messages.psd1` and a small, documented lookup helper. English source strings are the fallback; add German translations to the German catalog.
- Every script starts with comment-based help containing `.SYNOPSIS`, `.DESCRIPTION`, at least one `.EXAMPLE`, and `.NOTES` listing dependencies.
- Keep user-facing documentation in both top-level `README.md` / `README.de.md` and each tool folder's `README.md` / `README.de.md`. Update all applicable README files whenever script content, behavior, parameters, or user workflows change; keep the English and German versions consistent.
- Each README starts with one note line that links to the other language version (for example, `> Deutsche Version: [README.de.md](README.de.md)`). Do not add "Documentation" or "Related Documentation" sections at the end.
- The top-level README links to a tool folder's README only in the chapter that describes that tool, and only to the version in the same language. Tool READMEs do not link back to the top-level README.
- Every tool folder README follows the structure of `pdf\README.md`, which is the blueprint: language note, intro, `## Quick start`, `## Dependency setup` (if any), `## Scripts and switches` with one `### \`Script.ps1\`` section per public script (description, parameter and switch table, examples), `## Shared PowerShell parameters` (if any), and `## Safety and behavior`. Use this structure even when a folder has only one public script. The `Documentation` or `Related Documentation` sections are not used. The top-level README follows the same per-tool structure.
- PowerShell script documentation (comment-based help, parameter descriptions, examples, and notes) must remain complete and current in English only. Update it whenever script behavior or interface changes.
- User-facing English and German READMEs at the repository root and in each tool folder must remain synchronized with script behavior, parameters, and workflows.
- Every PowerShell script or module file (`.ps1`, `.psm1`) has a filename in the approved `Verb-Noun` form, whether user-facing or internal. Check the verb with `Get-Verb`; use a specific noun that clearly describes the file's action or responsibility. Update every caller, example, and documentation reference when a file is renamed.
- PowerShell helper scripts or modules that are not intended to be run directly belong in an `internal` or other clearly named subfolder, not beside user-facing scripts. Their filenames must also follow the approved `Verb-Noun` form, and callers must resolve them with paths relative to `$PSScriptRoot`.
- Every PowerShell function has a complete comment-based-help block immediately before its definition or at the start of its script block. Include `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` for every parameter, and `.OUTPUTS`. Add `.EXAMPLE` and `.NOTES` when they clarify usage or dependencies.
- Every PowerShell function and user-defined method follows the `ApprovedVerb-Noun` pattern. Check every prefix against `Get-Verb`; do not assume a familiar English verb is approved. Use a specific noun, and update callers and tests whenever a function or method is renamed.
- Comment on non-obvious decisions and explain why. Do not add comments that merely restate obvious code; use short section headings to structure the main script.

## Code structure and testability
- Every tool folder has a top-level script for the user-facing flow. The script contains only parameter handling, the console flow, and calls to functions. Load helpers by dot-sourcing them with paths relative to `$PSScriptRoot`.
- Every other function lives in its own file in the tool folder's `internal` subfolder, or in `common\internal` when shared (see below). The file contains exactly one function and is named after it (`Verb-Noun.ps1`). Do not define functions inside top-level scripts.
- Internal functions used by more than one tool folder live in `common\internal\` (one function per file, same `Verb-Noun.ps1` rule). Their mirror tests live in `tests\common\internal\`. Internal functions used by only one tool folder stay in that folder's `internal\`.
- Internal functions are written for testability:
  - All inputs are parameters, and all results are returned as objects. Do not read `$script:` variables, environment variables, or user profile folders inside a function; pass those values in explicitly. Callers may gather them.
  - Do not write to the console or prompt the user inside an internal function (no `Write-Host` and no `Read-Host`). Console output and prompts belong to the top-level script, which reports the returned results.
  - Keep side effects (file system, processes, registry, network) in narrow functions. Logic that only transforms data must not touch the file system or processes, so tests need little or no mocking.
- Every internal file has exactly one mirror test file at `tests\<tool>\internal\<Verb-Noun>.Tests.ps1`. New internal code aims for near 100% coverage; existing code is covered step by step.
- Top-level scripts keep a skipped placeholder test in `tests\<tool>\` until their flow is covered by tests.

## PowerShell style
- Set `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` near the start of every script.
- Use `[CmdletBinding()]` on scripts and functions; mark required parameters with `[Parameter(Mandatory)]`.
- Report user-facing status and errors through `Write-Host`, `Write-Warning`, or `Write-Error`, not `Write-Output`.
- Follow one console layout in every user-facing script (all texts localized):
  - Start with the shared document-style ASCII banner (cyan; two upper-case lines inside the box for the title and the key actions), followed by one or two indented cyan tagline lines and a blank line.
  - Open the run with a cyan `=== <Tool>: processing started ===` header, followed by plain lines for the effective settings and the number of items.
  - Mark each processed item with a cyan `--- <Item> n/N: <name> ---` line after a blank line. Show success in green, notices in dark yellow, and problems through `Write-Warning`. A failure of one item is recorded and does not stop the remaining items.
  - End with a cyan `=== Summary ===` block: `Path:` line, `Succeeded: x, skipped: y, failed: z`, totals where meaningful, then `Failed ...:` and `Skipped ...:` lists (`  None.` when empty, otherwise `  - <name> (<reason>)` in yellow). Preview runs (`-WhatIf`) still print the summary.
  - Report fatal errors as one concise message without a stack trace and end with exit code 1; do not let raw exceptions reach the console.
  - Sections that do not apply (for example item lines or the summary in interactive configuration tools) may be omitted; the banner and the error handling are always required.
- Use `-LiteralPath` and `Join-Path` consistently. Normalize user input with `Trim()` and `ExpandEnvironmentVariables()` before use.
- Start external console programs with redirected streams and read asynchronously so errors are not mistaken for PowerShell terminating errors and large output cannot block a pipe. Exception: run OCRmyPDF without stream redirection so its progress bar is displayed live.
- Save PowerShell scripts with a UTF-8 BOM (U+FEFF). Windows PowerShell 5.1 otherwise interprets non-ASCII text as ANSI.
- License the project and its files under the MIT License. Keep the standard license text in the root `LICENSE.md` and add an SPDX-License-Identifier: MIT header and the project copyright notice to every PowerShell script and PowerShell data file. Place headers after the required script help block.
- Include a `Contributors` section in every code file, listing the contributors and contact details explicitly approved for attribution.

## Dependencies and installation
- Scripts that only process or inspect user files must not install software and should not require administrator rights.
- Dependency-installation scripts must inspect the current dependency state first and elevate only when required. Before any UAC prompt, show the exact planned operations and require explicit confirmation. Install packages into the selected runtime; do not use user-scoped package options that can target a different interpreter.
- Reuse shared internal helpers from `common\internal\` for runtime discovery and other behavior used by multiple scripts. Resolve helper paths relative to `$PSScriptRoot`, prefer a working interpreter in the current user's profile, and invoke the resolved executable directly. Use a launcher only to discover a concrete runtime path when direct discovery fails.
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

## Testing
- The structure below `tests` mirrors the code structure. Example: `nextcloud\internal\Get-UserFolders.ps1` is tested in `tests\nextcloud\internal\Get-UserFolders.Tests.ps1`.
- Every production `.ps1` file has exactly one mirror test file. `tests\Static.Tests.ps1` enforces this.
- Global tests, such as repository-wide code analysis, stay directly in `tests`, but only if they apply to all files.
- Shared test helpers (for example `tests\TestHelpers.ps1`) stay in `tests`.
- Functions in `internal` must be testable: pass all inputs and outputs explicitly (parameters and return values) so that little or no mocking is needed. Avoid reading `$script:` state or user folders inside helpers.
- New code aims for near 100% coverage. Existing code is covered step by step. Legacy scripts with top-level flow have a skipped placeholder test until they are refactored into functions.
- Run `tests\Invoke-Tests.ps1` (add `-Coverage` for coverage of `internal` files). The tests must pass on Windows PowerShell 5.1 and PowerShell 7.
- Every `.ps1` file, including tests, is saved with a UTF-8 BOM.
