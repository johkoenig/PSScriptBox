# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Placeholder for the unit tests of pdf\Remove-PdfBackups.ps1.

.DESCRIPTION
    The script runs its main logic at top level and has no unit tests yet. The
    test is skipped until the script is refactored into testable functions
    (see AGENTS.md).

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

Describe 'Remove-PdfBackups' {
    It 'top-level script flow is not unit tested; helpers are covered in tests\pdf\internal' -Skip {
    }
}
