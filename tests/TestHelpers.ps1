# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
<#
.SYNOPSIS
    Shared Pester helpers for loading script functions without running scripts.

.DESCRIPTION
    Scripts in this repository execute their main logic at top level, so they
    cannot be dot-sourced in tests. The helpers parse a script with the
    PowerShell AST and return only the requested function definitions.

.NOTES
    Dependencies: Pester 5 or later.
#>

<#
.SYNOPSIS
    Returns a script block that defines the named functions from a script file.

.DESCRIPTION
    Dot-source the returned block inside a test scope so the functions become
    available there. Top-level statements of the script are not executed.

.PARAMETER ScriptPath
    Path to the .ps1 file that contains the functions.

.PARAMETER Name
    Names of the functions to extract.

.OUTPUTS
    System.Management.Automation.ScriptBlock. Definitions of the requested functions.
#>
function Get-ScriptFunctionBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ScriptPath,
        [Parameter(Mandatory)][string[]] $Name
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Parse errors in ${ScriptPath}: $($parseErrors[0].Message)"
    }

    $texts = foreach ($functionName in $Name) {
        $definition = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $functionName
            }, $true) | Select-Object -First 1
        if ($null -eq $definition) {
            throw "Function '$functionName' not found in $ScriptPath."
        }
        $definition.Extent.Text
    }
    return [scriptblock]::Create(($texts -join "`r`n`r`n"))
}
