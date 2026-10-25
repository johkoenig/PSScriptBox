# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Static checks for all PowerShell files in the repository (test step 1).

.DESCRIPTION
    Verifies syntax, UTF-8 BOM, StrictMode, comment-based help, approved verbs,
    the -EnglishOutput switch, and that every localized message used in code
    has a German entry in the area's message catalog. No script is executed.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $allFiles = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter '*.ps1' -File |
            Where-Object { $_.FullName -notmatch '\\(\.git|tests)\\' })

    $script:Files = @($allFiles | ForEach-Object {
            @{
                Name = $_.FullName.Substring($repoRoot.Length + 1)
                Path = $_.FullName
            }
        })
    $script:TopLevelScripts = @($script:Files | Where-Object { $_.Name -notmatch '\\internal\\' })
    $script:Mirrors = @($script:Files | ForEach-Object {
            @{
                Name   = $_.Name
                Mirror = Join-Path $repoRoot ('tests\' + $_.Name.Substring(0, $_.Name.Length - 4) + '.Tests.ps1')
            }
        })
}

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot

    function Get-Ast {
        param([string] $Path)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        [pscustomobject]@{ Ast = $ast; Errors = $errors }
    }
}

Describe 'Test mirror structure' {
    It '<Name> has a mirror test file under tests' -ForEach $script:Mirrors {
        $Mirror | Should -Exist
    }
}

Describe 'Syntax and encoding' {
    It '<Name> parses without errors' -ForEach $script:Files {
        (Get-Ast -Path $Path).Errors | Should -BeNullOrEmpty
    }

    It '<Name> starts with a UTF-8 BOM' -ForEach $script:Files {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $bytes.Length | Should -BeGreaterOrEqual 3
        ($bytes[0..2] -join ',') | Should -Be '239,187,191'
    }
}

Describe 'Script conventions' {
    It '<Name> enables StrictMode Latest' -ForEach $script:TopLevelScripts {
        $ast = (Get-Ast -Path $Path).Ast
        $strict = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Set-StrictMode'
            }, $true)
        $strict.Count | Should -BeGreaterThan 0
    }

    It '<Name> has a comment-based help block with synopsis and example' -ForEach $script:TopLevelScripts {
        $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $helpBlock = [regex]::Match($text, '<#.*?#>', 'Singleline').Value
        $helpBlock | Should -Match '\.SYNOPSIS\s+\S'
        $helpBlock | Should -Match '\.EXAMPLE\s+\S'
    }

    It '<Name> offers the -EnglishOutput switch' -ForEach $script:TopLevelScripts {
        $params = (Get-Ast -Path $Path).Ast.ParamBlock.Parameters.Name.VariablePath.UserPath
        $params | Should -Contain 'EnglishOutput'
    }
}

Describe 'Function conventions' {
    It 'every function in <Name> has help' -ForEach $script:Files {
        $functions = (Get-Ast -Path $Path).Ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true)
        foreach ($function in $functions) {
            $function.GetHelpContent() | Should -Not -BeNullOrEmpty -Because "$($function.Name) needs help"
        }
    }

    It 'every function in <Name> uses an approved verb' -ForEach $script:Files {
        $approved = (Get-Verb).Verb
        $functions = (Get-Ast -Path $Path).Ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true)
        foreach ($function in $functions) {
            $verb = $function.Name.Split('-')[0]
            $approved | Should -Contain $verb -Because "$($function.Name) uses an unapproved verb"
        }
    }
}

Describe 'Localization catalog' {
    It 'every Get-LocalizedText key in <Name> exists in its German catalog' -ForEach $script:Files {
        $areaDirectory = Split-Path -Parent $Path
        if ($areaDirectory -like '*\internal') { $areaDirectory = Split-Path -Parent $areaDirectory }

        $calls = (Get-Ast -Path $Path).Ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Get-LocalizedText'
            }, $true)
        if ($calls.Count -eq 0) { Set-ItResult -Skipped -Because 'no localized messages'; return }

        $catalogPath = Join-Path $areaDirectory 'l10n\de-DE\Messages.psd1'
        $catalogPath | Should -Exist
        $catalog = Import-PowerShellDataFile -LiteralPath $catalogPath

        foreach ($call in $calls) {
            # Element 0 is the command name itself, so the message key is the first string after it.
            $firstArgument = $call.CommandElements | Select-Object -Skip 1 | Where-Object {
                $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                $_ -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
            } | Select-Object -First 1
            if ($null -eq $firstArgument) { continue }
            $catalog.ContainsKey($firstArgument.Value) | Should -BeTrue -Because "missing German text for '$($firstArgument.Value)'"
        }
    }
}
