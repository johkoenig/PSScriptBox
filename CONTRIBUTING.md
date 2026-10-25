# Contributing

Contributions are welcome. Please open an issue before making a substantial or
behavior-changing contribution so the proposed scope can be discussed.

## Before submitting

- Keep changes focused and follow the repository guidance in `AGENTS.md`.
- Update the English and German README files at the repository root and in the
  affected tool folder when user-visible behavior, parameters, or workflows
  change.
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

Before submitting a change, run the smallest relevant checks available. For
PowerShell changes, parse the affected scripts and test applicable behavior
without using personal or confidential documents. Review `git diff` and
`git diff --check` to ensure the change contains only intended source and
documentation.

## Use of AI tools

AI coding assistants may be used for research, implementation, and review.
Contributors remain responsible for every submitted change, including its
correctness, security, licensing, privacy, testing, and user impact. Review and
understand generated code before submitting it, and do not provide confidential
data or credentials to an AI service.

## Pull requests

Describe the user-visible change, relevant implementation details, and the
validation performed. Call out limitations or behavior changes clearly.
