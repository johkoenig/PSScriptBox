<#
.SYNOPSIS
    Entfernt gesicherte Originaldateien, wenn die bearbeitete Datei vorhanden ist.

.DESCRIPTION
    Durchsucht einen Ordner rekursiv nach Dateien mit dem Suffix _orig vor der
    Dateiendung. Eine Sicherung wird nur gelöscht, wenn im selben Ordner die
    gleichnamige Datei ohne _orig-Suffix existiert. Mit -WhatIf lässt sich die
    Löschliste gefahrlos anzeigen.

.PARAMETER InputPath
    Ordner, der rekursiv nach passenden _orig-Dateien durchsucht werden soll.

.EXAMPLE
    .\Clean-Originals.ps1 -InputPath 'C:\PDFs' -WhatIf
    Zeigt an, welche _orig-Dateien gelöscht würden.

.EXAMPLE
    .\Clean-Originals.ps1 -InputPath 'C:\PDFs'
    Fragt vor dem Löschen jeder passenden _orig-Datei nach Bestätigung.

.NOTES
    Abhängigkeiten: PowerShell 5.1 oder neuer. Es werden keine zusätzlichen
    Programme oder Module benötigt.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $InputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$InputPath = [Environment]::ExpandEnvironmentVariables($InputPath.Trim().Trim('"'))
if (-not (Test-Path -LiteralPath $InputPath -PathType Container)) {
    throw "Der angegebene Ordner wurde nicht gefunden: $InputPath"
}

$directory = Get-Item -LiteralPath $InputPath
$basePathPrefix = $directory.FullName
if (-not $basePathPrefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar)) {
    $basePathPrefix += [System.IO.Path]::DirectorySeparatorChar
}
$pathSegments = @($directory.FullName.TrimEnd('\') -split '[\\/]' | Where-Object { $_ })
$pathTail = @($pathSegments | Select-Object -Last 3)
$summaryPath = if ($pathTail.Count -gt 0) { '.\' + ($pathTail -join '\') + '\' } else { '.\' }
$originalFiles = @(Get-ChildItem -LiteralPath $directory.FullName -File -Recurse -Force |
    Where-Object { $_.BaseName -match '_orig$' })

$eligibleFiles = @(
    foreach ($originalFile in $originalFiles) {
        $processedBaseName = $originalFile.BaseName -replace '_orig$', ''
        $processedPath = Join-Path -Path $originalFile.DirectoryName -ChildPath ($processedBaseName + $originalFile.Extension)
        if (Test-Path -LiteralPath $processedPath -PathType Leaf) {
            $originalFile
        }
    }
)
$eligibleCount = $eligibleFiles.Count
$deletedCount = 0

Write-Host ''
Write-Host '       .-----------------------------------------------.' -ForegroundColor Cyan
Write-Host '       |  +----------------+                           |' -ForegroundColor Cyan
Write-Host '       |  |  _orig  ->  X  |       CLEAN ORIGINALS      |' -ForegroundColor Cyan
Write-Host '       |  +----------------+                           |' -ForegroundColor Cyan
Write-Host '       ''-----------------------------------------------''' -ForegroundColor Cyan
Write-Host "  Ordner: $($directory.FullName)"
Write-Host "  Zu löschende Dateien: $eligibleCount" -ForegroundColor Yellow

if ($eligibleCount -eq 0) {
    Write-Host 'Keine passenden _orig-Dateien mit vorhandener bearbeiteter Datei gefunden.' -ForegroundColor Green
    Write-Host ''
    Write-Host '=== Zusammenfassung ===' -ForegroundColor Cyan
    Write-Host "Pfad: $summaryPath"
    Write-Host 'Gefunden: 0'
    Write-Host 'Gelöscht: 0'
    return
}

Write-Host ''
foreach ($originalFile in $eligibleFiles) {
    $relativePath = $originalFile.FullName.Substring($basePathPrefix.Length)
    Write-Host "  - $relativePath"
}

if ($WhatIfPreference) {
    Write-Host ''
    Write-Host 'Vorschau: Es wurden keine Dateien gelöscht.' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '=== Zusammenfassung ===' -ForegroundColor Cyan
    Write-Host "Pfad: $summaryPath"
    Write-Host "Gefunden: $eligibleCount"
    Write-Host 'Gelöscht: 0'
    return
}

$approvedFiles = @(
    foreach ($originalFile in $eligibleFiles) {
        $processedBaseName = $originalFile.BaseName -replace '_orig$', ''
        $processedPath = Join-Path -Path $originalFile.DirectoryName -ChildPath ($processedBaseName + $originalFile.Extension)
        $relativePath = $originalFile.FullName.Substring($basePathPrefix.Length)
        $relativeProcessedPath = $processedPath.Substring($basePathPrefix.Length)
        $action = "Gesicherte Originaldatei löschen; bearbeitete Datei bleibt erhalten: $relativeProcessedPath"
        if ($PSCmdlet.ShouldProcess($relativePath, $action)) {
            $originalFile
        }
    }
)

if ($approvedFiles.Count -gt 0) {
    Write-Host ''
    Write-Host 'Lösche gesicherte Originale...' -ForegroundColor Cyan
}

foreach ($originalFile in $approvedFiles) {
    $relativePath = $originalFile.FullName.Substring($basePathPrefix.Length)
    Remove-Item -LiteralPath $originalFile.FullName -Force
    Write-Host "  Gelöscht: $relativePath" -ForegroundColor Green
    $deletedCount++
}

Write-Host ''
Write-Host '=== Zusammenfassung ===' -ForegroundColor Cyan
Write-Host "Pfad: $summaryPath"
Write-Host "Gefunden: $eligibleCount"
Write-Host "Gelöscht: $deletedCount"
