# Open issues

Planned work that is not yet tracked as GitHub issues. Each entry is a draft for a future issue.

## 1. Copy the Copilot instructions from the old script repo

Copy the relevant Copilot instruction files (for example `.github/copilot-instructions.md`) from the old script repository into this repository. Reconcile them with `AGENTS.md` so that no rules contradict each other.

## 2. Split the PDF processor into an OCR script and a filesize optimizer script

Separate OCR (OCRmyPDF) from file size optimization (the Ghostscript stage) into two independent scripts. Each gets its own parameters, tests, and README section.

## 3. Remove the initialize script from the pdf folder; only check dependencies

Remove `pdf/Initialize-PdfProcessor.ps1`. The scripts should only check for dependencies and report missing ones with install hints. They must not install anything.

## 4. Add a PowerShell module file

Evaluate and add a module manifest and script module (`.psd1` / `.psm1`) that exposes the public functions. Decide the export list and keep the one-function-per-file layout.

## 5. Set up branch policies on GitHub

Protect the default branch: require pull request reviews, require passing status checks (tests), and block force pushes.

## 6. Set up a pipeline on GitHub

Add a GitHub Actions workflow that runs `tests/Invoke-Tests.ps1 -Coverage` on Windows PowerShell 5.1 and on PowerShell 7. Upload the JaCoCo coverage file as a workflow artifact.

## 7. Extract all Write-Host calls into separate Show-* cmdlets

Move every `Write-Host` call into dedicated `Show-*` functions in the relevant `internal` folder (or `common/internal`). This keeps console output testable and keeps business logic free of console I/O.

## 8. Raise the test coverage target to 98 %

Set the coverage target to 98 % for new code and raise the coverage of existing code step by step. Update the threshold in `tests/Invoke-Tests.ps1` once the target is reached.

## 9. Make Get-LocalizedText accept an explicit or implicit language and a path to the language file

Currently `Get-LocalizedText` takes `-Language` and `-Messages` as explicit parameters, and it falls back to `$script:OutputLanguage` and `$script:GermanMessages` when they are omitted. This breaks the rule in `AGENTS.md` against reading `$script:` variables inside functions.

Change the design as follows:

- `-Language` can be given explicitly. If it is omitted, the language is derived implicitly (for example from the Windows display language), and the function does not read script-scope variables.
- Replace `-Messages` with a relative path to the language file (for example `l10n\de-DE\Messages.psd1`). The function loads the catalog from that path.
- Update all call sites in `pdf`, `nextcloud`, `git`, and `common`, and update the mirror tests.

## 10. Finish the README review for nextcloud and git

Review `nextcloud/README.md`, `nextcloud/README.de.md`, `git/README.md`, and `git/README.de.md` line by line against `pdf/README.md`. They were restructured by an agent and only spot-checked. Check that each README is function by function, has no "Documentation" block, and has the language note at the top.

## 11. Add a line-ending policy (.gitattributes)

Git warns that CRLF is converted to LF in the working copy. Decide on a line-ending policy and add a `.gitattributes` file. Apply it consistently to all text files.

## 12. Resolve the remaining PSScriptAnalyzer findings

Fix or consciously suppress the remaining rules. `PSUseSingularNouns` and `PSUseShouldProcess` are still open. `PSAvoidUsingWriteHost` is covered by issue 7.

## 13. Verify that README.md and README.de.md have the same structure

Check that the root and all sub-folder READMEs have the same structure in English and German. Check that the language note is at the top, and that sub-READMEs link back to the root only if the rules say so.
