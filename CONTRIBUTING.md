# Contributing

Contributions are welcome. Please open an issue before making a substantial or
behavior-changing contribution so the proposed scope can be discussed.

## Before submitting

- Keep changes focused and follow the repository guidance in `AGENTS.md`.
- Write all code, comments, and code documentation in English. German text belongs
  only in the German message catalog and in console messages.
- Put each function in its own file in the tool's `internal` folder, or in `common\internal` if more than one tool folder uses it, named `Verb-Noun.ps1`. Keep top-level scripts limited to parameters, the console flow,
  and calls to those functions. Make internal functions testable: pass inputs as
  parameters, return results, and keep console output, prompts, and side effects
  out of pure logic.
- Add one mirror test file for each new PowerShell file under `tests\`, following the
  folder structure of the code (`common\internal` maps to `tests\common\internal`). Aim for near 100% coverage of new code.
- Structure every tool README like `pdf\README.md` (function by function), even when a folder has only one public script. See `AGENTS.md`.
- Update the English and German README files at the repository root and in the
  affected tool folder when user-visible behavior, parameters, or workflows
  change. Start each README with a note linking to the other language version,
  and do not add "Documentation" sections at the end.
- Keep PowerShell comment-based help complete and current in English.
- Use approved PowerShell verbs for script and function names.
- Do not commit PDFs, generated binaries, temporary files, secrets, tokens, or
  personal data. User-specific paths and account information must be discovered
  at runtime rather than embedded in scripts.
- Preserve user input files unless the documented operation explicitly replaces
  them, and explain any behavior that can change or delete user data.
- Follow the project's MIT license and retain applicable license and contributor
  notices.

## Validation

Before submitting a change, run the test suite with `tests\Invoke-Tests.ps1` on
Windows PowerShell 5.1 and PowerShell 7. Add `-Coverage` to check internal helper
coverage. Parse the affected scripts and test applicable behavior without using
personal or confidential documents. Review `git diff` and `git diff --check` to
ensure the change contains only intended source and documentation.

## Use of AI tools

AI coding assistants may be used for research, implementation, and review.
Contributors remain responsible for every submitted change, including its
correctness, security, licensing, privacy, testing, and user impact. Review and
understand generated code before submitting it, and do not provide confidential
data or credentials to an AI service.

## Pull requests

Describe the user-visible change, relevant implementation details, and the
validation performed. Call out limitations or behavior changes clearly.
