# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
<#
.SYNOPSIS
    Unit tests for pdf\internal\Optimize-WithGhostscript.ps1.

.DESCRIPTION
    Covers the failure paths with a nonexistent Ghostscript executable, which
    must leave the input untouched. The size-reduction path needs a real
    Ghostscript and is skipped when none is installed.

.NOTES
    Dependencies: Pester 5 or later. Run through tests\Invoke-Tests.ps1.
    Optional: Ghostscript (gswin64c, gswin32c, or gs) for the success test.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\ConvertTo-QuotedArgument.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Get-ExecutablePath.ps1')
    . (Join-Path $PSScriptRoot '..\..\..\pdf\internal\Optimize-WithGhostscript.ps1')

    $script:GsPath = @('gswin64c', 'gswin32c', 'gs') |
        ForEach-Object { Get-ExecutablePath -Name $_ } | Where-Object { $_ } | Select-Object -First 1
}

Describe 'Optimize-WithGhostscript' {
    BeforeEach {
        $script:Pdf = Join-Path $TestDrive ('scan-{0}.pdf' -f [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllBytes($script:Pdf, [byte[]](1..64))
    }

    It 'returns $false and leaves the input untouched when Ghostscript cannot be started' {
        $before = (Get-Item -LiteralPath $script:Pdf).Length
        $result = Optimize-WithGhostscript -GhostscriptPath 'C:\scriptbox-no-such\gs.exe' -Pdf (Get-Item -LiteralPath $script:Pdf) -Dpi 200
        $result | Should -BeFalse
        (Get-Item -LiteralPath $script:Pdf).Length | Should -Be $before
    }

    It 'removes no temporary file in the input folder after a failure' {
        Optimize-WithGhostscript -GhostscriptPath 'C:\scriptbox-no-such\gs.exe' -Pdf (Get-Item -LiteralPath $script:Pdf) -Dpi 200 | Out-Null
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $script:Pdf) -Filter '.*.gs.pdf.part' -Force).Count | Should -Be 0
    }

    It 'returns $false when Ghostscript exits with an error' {
        if (-not $script:GsPath) { Set-ItResult -Skipped -Because 'Ghostscript is not installed'; return }
        # An unreadable input makes Ghostscript fail, so no optimized file is produced.
        $broken = Join-Path $TestDrive 'broken.pdf'
        [System.IO.File]::WriteAllBytes($broken, [byte[]](0, 1, 2))
        Optimize-WithGhostscript -GhostscriptPath $script:GsPath -Pdf (Get-Item -LiteralPath $broken) -Dpi 200 | Should -BeFalse
    }
}
