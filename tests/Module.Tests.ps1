# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>
<#
.SYNOPSIS
    Tests for the PSScriptBox module manifest and script module.

.DESCRIPTION
    Verifies that the manifest is valid and lists exactly the public command files,
    that the module files carry a UTF-8 BOM and parse cleanly, that every public
    command file defines its command as a function with comment-based help and a
    direct-run guard, that importing the module exports exactly the public commands
    (and no internal helpers), and that an exported command runs end to end in a
    temporary Git repository, both as a module function and as a directly executed
    script file.

.NOTES
    Dependencies: Pester 5 or later, Git. Run through tests\Invoke-Tests.ps1.
#>

BeforeDiscovery {
    # -ForEach data is evaluated during discovery, so the shared fixtures are set here.
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:RepoRoot 'PSScriptBox.psd1'
    $script:ModulePath = Join-Path $script:RepoRoot 'PSScriptBox.psm1'
    $script:PublicFiles = @(Get-ChildItem -LiteralPath $script:RepoRoot -Recurse -File -Filter '*.ps1' |
            Where-Object { $_.FullName -notmatch '[\\/]internal[\\/]' -and $_.FullName -notmatch '[\\/](tests|\.git)[\\/]' } |
            ForEach-Object { @{ Name = $_.BaseName; Path = $_.FullName } } |
            Sort-Object -Property Name)
    $script:ModuleFiles = @(
        @{ Name = 'PSScriptBox.psd1'; Path = $script:ManifestPath }
        @{ Name = 'PSScriptBox.psm1'; Path = $script:ModulePath }
    )
    $script:ExpectedCommands = @($script:PublicFiles | ForEach-Object { $_.Name } | Sort-Object)
}

BeforeAll {
    # Re-derived for the run pass; Pester re-invokes the file and BeforeDiscovery state is not shared with it.
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:RepoRoot 'PSScriptBox.psd1'
    $script:ModulePath = Join-Path $script:RepoRoot 'PSScriptBox.psm1'
    $script:ExpectedCommands = @(Get-ChildItem -LiteralPath $script:RepoRoot -Recurse -File -Filter '*.ps1' |
            Where-Object { $_.FullName -notmatch '[\\/]internal[\\/]' -and $_.FullName -notmatch '[\\/](tests|\.git)[\\/]' } |
            ForEach-Object { $_.BaseName } | Sort-Object)

    function New-ModuleTestRepository {
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $path | Out-Null
        & git init --quiet -b main $path | Out-Null
        Push-Location -LiteralPath $path
        try {
            & git -c user.name='PSScriptBox Test' -c user.email='test@example.invalid' commit --quiet --allow-empty -m init
            & git branch obsolete-feature
        }
        finally {
            Pop-Location
        }
        return $path
    }
}

AfterAll {
    Remove-Module -Name PSScriptBox -Force -ErrorAction SilentlyContinue
}

Describe 'Module manifest' {
    It 'exists at the repository root' {
        Test-Path -LiteralPath $script:ManifestPath -PathType Leaf | Should -BeTrue
    }

    It 'is valid' {
        { Test-ModuleManifest -Path $script:ManifestPath } | Should -Not -Throw
    }

    It 'uses PSScriptBox.psm1 as the root module' {
        (Test-ModuleManifest -Path $script:ManifestPath).RootModule | Should -Be 'PSScriptBox.psm1'
    }

    It 'requires PowerShell 5.1 or later' {
        (Test-ModuleManifest -Path $script:ManifestPath).PowerShellVersion | Should -Be ([version]'5.1')
    }

    It 'lists exactly the public command files in FunctionsToExport' {
        $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
        @($manifest.FunctionsToExport | Sort-Object) | Should -Be $script:ExpectedCommands
    }
}

Describe 'Module files' {
    It 'PSScriptBox.psm1 exists at the repository root' {
        Test-Path -LiteralPath $script:ModulePath -PathType Leaf | Should -BeTrue
    }

    It '<Name> starts with a UTF-8 BOM' -ForEach $script:ModuleFiles {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        ($bytes[0..2] -join ',') | Should -Be '239,187,191'
    }

    It 'PSScriptBox.psm1 parses without errors' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:ModulePath, [ref]$tokens, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }
}

Describe 'Public command files' {
    It '<Name> defines its command as one function with comment-based help' -ForEach $script:PublicFiles {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        $errors | Should -BeNullOrEmpty
        $functions = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
            }, $true))
        $functions.Count | Should -Be 1
        $functions[0].GetHelpContent().Synopsis | Should -Not -BeNullOrEmpty
    }

    It 'dot-sourcing <Name> does not run the command flow' -ForEach $script:PublicFiles {
        $scriptPath = $Path
        $output = @(& { . $scriptPath })
        $output | Should -BeNullOrEmpty
    }
}

Describe 'Module import' {
    BeforeAll {
        Import-Module -Name $script:ManifestPath -Force
    }

    It 'exports exactly the public commands' {
        $exported = @((Get-Module -Name PSScriptBox).ExportedCommands.Keys | Sort-Object)
        $exported | Should -Be $script:ExpectedCommands
    }

    It 'does not export internal helpers' {
        $exported = @((Get-Module -Name PSScriptBox).ExportedCommands.Keys)
        $exported | Should -Not -Contain 'Get-LocalizedText'
        $exported | Should -Not -Contain 'Get-MissingDependencyReport'
        $exported | Should -Not -Contain 'Invoke-GitCommand'
    }

    It 'gives every exported command comment-based help' {
        foreach ($commandName in $script:ExpectedCommands) {
            (Get-Help -Name $commandName).Synopsis | Should -Not -BeNullOrEmpty -Because "$commandName needs a synopsis"
        }
    }
}

Describe 'Exported command execution' {
    BeforeAll {
        Import-Module -Name $script:ManifestPath -Force
        $script:PreviousGlobal = $env:GIT_CONFIG_GLOBAL
        $script:PreviousSystem = $env:GIT_CONFIG_SYSTEM
        $script:PreviousPath = $env:PATH
        $env:GIT_CONFIG_GLOBAL = Join-Path $TestDrive 'module-global.gitconfig'
        $env:GIT_CONFIG_SYSTEM = Join-Path $TestDrive 'module-system.gitconfig'

        # The Git commands look up git.exe (a Windows application name); on other platforms provide a shim.
        if ($env:OS -ne 'Windows_NT') {
            $shimDirectory = Join-Path $TestDrive 'shim'
            New-Item -ItemType Directory -Path $shimDirectory | Out-Null
            $shimPath = Join-Path $shimDirectory 'git.exe'
            Set-Content -LiteralPath $shimPath -Value @('#!/bin/sh', 'exec git "$@"') -Encoding ascii
            & chmod 0755 $shimPath
            $env:PATH = $shimDirectory + [System.IO.Path]::PathSeparator + $env:PATH
        }
    }

    AfterAll {
        $env:GIT_CONFIG_GLOBAL = $script:PreviousGlobal
        $env:GIT_CONFIG_SYSTEM = $script:PreviousSystem
        $env:PATH = $script:PreviousPath
    }

    It 'Remove-ObsoleteGitBranches -WhatIf previews an obsolete branch in a temporary repository' {
        $repo = New-ModuleTestRepository
        Push-Location -LiteralPath $repo
        try {
            { Remove-ObsoleteGitBranches -WhatIf -EnglishOutput } | Should -Not -Throw
            @(& git branch --list obsolete-feature) | Should -Not -BeNullOrEmpty
        }
        finally {
            Pop-Location
        }
    }

    It 'running the script file directly still executes the command and keeps the branch under -WhatIf' {
        $repo = New-ModuleTestRepository
        $hostExe = if ($PSVersionTable.PSEdition -eq 'Desktop') {
            Join-Path $PSHOME 'powershell.exe'
        }
        elseif ($env:OS -eq 'Windows_NT') {
            Join-Path $PSHOME 'pwsh.exe'
        }
        else {
            Join-Path $PSHOME 'pwsh'
        }
        $scriptPath = Join-Path $script:RepoRoot 'git\Remove-ObsoleteGitBranches.ps1'
        $outputPath = Join-Path $TestDrive 'direct-run-output.txt'
        Push-Location -LiteralPath $repo
        try {
            $process = Start-Process -FilePath $hostExe -Wait -PassThru -NoNewWindow `
                -ArgumentList @('-NoProfile', '-File', $scriptPath, '-WhatIf', '-EnglishOutput') `
                -RedirectStandardOutput $outputPath -RedirectStandardError (Join-Path $TestDrive 'direct-run-error.txt')
            $process.ExitCode | Should -Be 0
            $output = Get-Content -LiteralPath $outputPath -Raw
            $output | Should -Match 'OBSOLETE GIT BRANCH CLEANUP'
            @(& git branch --list obsolete-feature) | Should -Not -BeNullOrEmpty
        }
        finally {
            Pop-Location
        }
    }
}
