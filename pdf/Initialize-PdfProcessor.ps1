<#
.SYNOPSIS
    Installs and verifies the dependencies for the PDF processing scripts.

.DESCRIPTION
    Checks the current dependency state before requesting elevation. If
    Chocolatey is unavailable, the script stops and asks the user to install it.
    Missing machine-wide software is installed from Chocolatey in an elevated
    PowerShell session after explicit confirmation. A user-scoped Python
    interpreter is preferred; Python packages are installed into the selected
    interpreter, elevated only when it is machine-wide. Tesseract language data
    is inspected but never downloaded automatically.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.PARAMETER ElevatedChild
    Internal switch used when the script restarts itself with administrator
    privileges.

.PARAMETER RuntimePythonPath
    Internal path used to preserve the selected interpreter during elevation.

.EXAMPLE
    .\Initialize-PdfProcessor.ps1
    Checks dependencies, installs missing software if needed, and reports
    missing Tesseract language data.

.EXAMPLE
    .\Initialize-PdfProcessor.ps1 -EnglishOutput
    Runs the setup with English console output.

.NOTES
    Dependencies: Windows PowerShell 5.1 or later and Chocolatey. Chocolatey
    must be installed separately. System-wide installation requires
    administrator privileges. Python packages are installed in the selected
    interpreter. No OCR language data is downloaded by this script.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

[CmdletBinding()]
param(
    [switch] $EnglishOutput,

    [Parameter(DontShow = $true)]
    [switch] $ElevatedChild,

    [Parameter(DontShow = $true)]
    [string] $RuntimePythonPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'internal\Get-PdfPythonRuntime.ps1')
. (Join-Path $PSScriptRoot '..\common\internal\Get-LocalizedText.ps1')
. (Join-Path $PSScriptRoot 'internal\ConvertTo-QuotedArgument.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-ExecutablePath.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-GhostscriptExecutablePath.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-SetupProcess.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-TesseractTrainingStatus.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-PdfToolLocation.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-ToolStatusLabel.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-PdfSetupState.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-PdfSetupStateReport.ps1')
. (Join-Path $PSScriptRoot 'internal\Start-ElevatedSetup.ps1')
. (Join-Path $PSScriptRoot 'internal\Update-ProcessPath.ps1')

$script:OutputLanguage = if (
    $EnglishOutput -or [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'de'
) { 'en' } else { 'de' }
$script:GermanMessages = if ($script:OutputLanguage -eq 'de') {
    Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1')
}
else { @{} }

$localizationOptions = @{ UiLanguage = $script:OutputLanguage; Messages = $script:GermanMessages }

# --- Gather and report the current state ----------------------------------


$setupHeader = @(
    '       .-------------------------------------------.'
    '      /                                           /|'
    '     /___________________________________________/ |'
    '     |  .-------------------------------------.  | |'
    '     |  | PDF PROCESSOR SETUP                 |  | |'
    '     |  | CHECK / INSTALL / VERIFY            |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)
Write-Host ''
foreach ($line in $setupHeader) { Write-Host $line -ForegroundColor Cyan }
Write-Host (Get-LocalizedText 'Checks and installs PDF processor dependencies.') -ForegroundColor Cyan

$toolLocation = Get-PdfToolLocation -PreferredPythonPath $RuntimePythonPath
$state = Get-PdfSetupState -ToolLocation $toolLocation @localizationOptions
foreach ($line in Get-PdfSetupStateReport -State $state @localizationOptions) {
    if ($line.Color) { Write-Host $line.Text -ForegroundColor $line.Color } else { Write-Host $line.Text }
}

if (-not $state.ChocolateyAvailable) {
    Write-Host ''
    if ($state.ChocolateyPath) {
        Write-Host (Get-LocalizedText 'Chocolatey was found, but its version check failed.') -ForegroundColor Yellow
        Write-Host (Get-LocalizedText 'Check the Chocolatey installation and make sure choco --version succeeds.')
    }
    else {
        Write-Host (Get-LocalizedText 'Chocolatey is required but was not found.') -ForegroundColor Yellow
        Write-Host (Get-LocalizedText 'Please install Chocolatey from https://chocolatey.org/install and run this script again.')
    }
    exit 1
}

$missingPackages = @()
if (-not $state.PythonAvailable) { $missingPackages += 'python' }
if (-not $state.TesseractAvailable) { $missingPackages += 'tesseract' }
if (-not $state.GhostscriptAvailable) { $missingPackages += 'ghostscript' }

$missingPythonPackages = @()
if (-not $state.OcrMyPdfAvailable) { $missingPythonPackages += 'ocrmypdf' }
if (-not $state.PikePdfAvailable) { $missingPythonPackages += 'pikepdf' }
$pythonPackagesNeedElevation = (
    $missingPythonPackages.Count -gt 0 -and $state.PythonScope -eq 'Machine'
)
$requiresElevation = $missingPackages.Count -gt 0 -or $pythonPackagesNeedElevation

if ($requiresElevation) {
    $isAdministrator = (
        [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdministrator -and -not $ElevatedChild) {
        Write-Host ''
        if ($missingPackages.Count -gt 0) {
            Write-Host (Get-LocalizedText -Text 'Chocolatey packages to install system-wide: {0}' -Arguments @(($missingPackages -join ', '))) -ForegroundColor Yellow
        }
        if (-not $state.PythonAvailable -and $missingPackages -contains 'python') {
            Write-Host (Get-LocalizedText 'After Python is installed, the setup will resolve that interpreter and check its required Python packages.')
        }
        if ($pythonPackagesNeedElevation) {
            Write-Host (Get-LocalizedText -Text 'Python packages to install in the selected machine-wide interpreter: {0}' -Arguments @(($missingPythonPackages -join ', '))) -ForegroundColor Yellow
            Write-Host (Get-LocalizedText -Text 'Selected Python interpreter: {0}' -Arguments @($state.PythonPath))
        }
        elseif ($missingPythonPackages.Count -gt 0 -and $state.PythonScope -eq 'User') {
            Write-Host (Get-LocalizedText -Text 'Python packages to install in the selected user interpreter after elevation: {0}' -Arguments @(($missingPythonPackages -join ', ')))
        }
        Write-Host (Get-LocalizedText 'Press Enter to continue to the administrator prompt, or type Q to cancel.')
        $confirmation = Read-Host
        if ($confirmation -match '^(q|quit|cancel)$') {
            Write-Host (Get-LocalizedText 'Setup cancelled; no elevated changes were started.')
            exit 0
        }
        if ($confirmation) {
            Write-Host (Get-LocalizedText 'Setup cancelled; press Enter without typing anything to continue.') -ForegroundColor Yellow
            exit 0
        }
        Write-Host (Get-LocalizedText 'Opening an elevated PowerShell window now...') -ForegroundColor Cyan
        try {
            $elevatedExitCode = Start-ElevatedSetup -ScriptPath $PSCommandPath -EnglishOutput $EnglishOutput.IsPresent -RuntimePythonPath $state.PythonPath
            if ($elevatedExitCode -ne 0) {
                Write-Error (Get-LocalizedText -Text 'Elevated installation failed (exit code {0}).' -Arguments @($elevatedExitCode))
                exit $elevatedExitCode
            }
            Update-ProcessPath -MachinePath ([Environment]::GetEnvironmentVariable('Path', 'Machine')) -UserPath ([Environment]::GetEnvironmentVariable('Path', 'User'))
            $toolLocation = Get-PdfToolLocation -PreferredPythonPath $RuntimePythonPath
            $state = Get-PdfSetupState -ToolLocation $toolLocation @localizationOptions
        }
        catch {
            Write-Error (Get-LocalizedText -Text 'Elevation failed or was cancelled: {0}' -Arguments @($_.Exception.Message))
            exit 1
        }
    }
    elseif (-not $isAdministrator -and $ElevatedChild) {
        Write-Error (Get-LocalizedText 'The elevated setup process does not have administrator privileges.')
        exit 1
    }
    elseif ($isAdministrator) {
        foreach ($package in $missingPackages) {
            Write-Host ''
            Write-Host (Get-LocalizedText -Text 'Installing Chocolatey package: {0}' -Arguments @($package)) -ForegroundColor Cyan
            $installResult = Invoke-SetupProcess -FilePath $state.ChocolateyPath -Arguments @('install', $package, '--yes') @localizationOptions
            if ($installResult.StdOut) { Write-Host $installResult.StdOut.TrimEnd() }
            if ($installResult.StdErr) { Write-Host $installResult.StdErr.TrimEnd() -ForegroundColor DarkYellow }
            if ($installResult.ExitCode -ne 0) {
                Write-Error (Get-LocalizedText -Text 'Chocolatey failed to install {0} (exit code {1}).' -Arguments @($package, $installResult.ExitCode))
                exit $installResult.ExitCode
            }
        }

        Update-ProcessPath -MachinePath ([Environment]::GetEnvironmentVariable('Path', 'Machine')) -UserPath ([Environment]::GetEnvironmentVariable('Path', 'User'))
        $toolLocation = Get-PdfToolLocation -PreferredPythonPath $RuntimePythonPath
        $state = Get-PdfSetupState -ToolLocation $toolLocation @localizationOptions
        if ($state.PythonScope -eq 'Machine') {
            $machinePythonPackages = @()
            if (-not $state.OcrMyPdfAvailable) { $machinePythonPackages += 'ocrmypdf' }
            if (-not $state.PikePdfAvailable) { $machinePythonPackages += 'pikepdf' }
            foreach ($package in $machinePythonPackages) {
                Write-Host ''
                Write-Host (Get-LocalizedText -Text 'Installing Python package in the machine-wide interpreter: {0}' -Arguments @($package)) -ForegroundColor Cyan
                $pipResult = Invoke-SetupProcess -FilePath $state.PythonPath -Arguments @('-m', 'pip', 'install', '--upgrade', $package) @localizationOptions
                if ($pipResult.StdOut) { Write-Host $pipResult.StdOut.TrimEnd() }
                if ($pipResult.StdErr) { Write-Host $pipResult.StdErr.TrimEnd() -ForegroundColor DarkYellow }
                if ($pipResult.ExitCode -ne 0) {
                    Write-Error (Get-LocalizedText -Text 'pip failed to install {0} (exit code {1}).' -Arguments @($package, $pipResult.ExitCode))
                    exit $pipResult.ExitCode
                }
            }
            $toolLocation = Get-PdfToolLocation -PreferredPythonPath $RuntimePythonPath
            $state = Get-PdfSetupState -ToolLocation $toolLocation @localizationOptions
            if (-not $state.OcrMyPdfAvailable -or -not $state.PikePdfAvailable) {
                Write-Error (Get-LocalizedText 'One or more dependencies are still missing after installation. Review the output above.')
                exit 1
            }
        }
    }

    if ($ElevatedChild) {
        if (-not $state.PythonAvailable -or -not $state.TesseractAvailable -or -not $state.GhostscriptAvailable) {
            Write-Error (Get-LocalizedText 'One or more Chocolatey packages are still missing after installation.')
            exit 1
        }
        if ($state.PythonScope -eq 'Machine') {
            $elevatedPythonPackages = @()
            if (-not $state.OcrMyPdfAvailable) { $elevatedPythonPackages += 'ocrmypdf' }
            if (-not $state.PikePdfAvailable) { $elevatedPythonPackages += 'pikepdf' }
            foreach ($package in $elevatedPythonPackages) {
                Write-Host ''
                Write-Host (Get-LocalizedText -Text 'Installing Python package in the machine-wide interpreter: {0}' -Arguments @($package)) -ForegroundColor Cyan
                $pipResult = Invoke-SetupProcess -FilePath $state.PythonPath -Arguments @('-m', 'pip', 'install', '--upgrade', $package) @localizationOptions
                if ($pipResult.StdOut) { Write-Host $pipResult.StdOut.TrimEnd() }
                if ($pipResult.StdErr) { Write-Host $pipResult.StdErr.TrimEnd() -ForegroundColor DarkYellow }
                if ($pipResult.ExitCode -ne 0) {
                    Write-Error (Get-LocalizedText -Text 'pip failed to install {0} (exit code {1}).' -Arguments @($package, $pipResult.ExitCode))
                    exit $pipResult.ExitCode
                }
            }
            $toolLocation = Get-PdfToolLocation -PreferredPythonPath $RuntimePythonPath
            $state = Get-PdfSetupState -ToolLocation $toolLocation @localizationOptions
            if (-not $state.OcrMyPdfAvailable -or -not $state.PikePdfAvailable) {
                Write-Error (Get-LocalizedText 'One or more dependencies are still missing after installation. Review the output above.')
                exit 1
            }
        }
        exit 0
    }

    if (-not $state.PythonAvailable -or -not $state.TesseractAvailable -or -not $state.GhostscriptAvailable) {
        Write-Error (Get-LocalizedText 'One or more Chocolatey packages are still missing after installation.')
        exit 1
    }
}

if ($ElevatedChild) {
    exit 0
}

# --- Install Python packages into the selected interpreter ---------------

$missingPythonPackages = @()
if (-not $state.OcrMyPdfAvailable) { $missingPythonPackages += 'ocrmypdf' }
if (-not $state.PikePdfAvailable) { $missingPythonPackages += 'pikepdf' }

if ($missingPythonPackages.Count -gt 0) {
    if (-not $state.PythonAvailable) {
        Write-Error (Get-LocalizedText 'Python is unavailable; Python packages cannot be checked or installed.')
        exit 1
    }
    Write-Host ''
    if ($state.PythonScope -eq 'User') {
        Write-Host (Get-LocalizedText 'Installing missing Python packages into the selected user Python interpreter (no elevation required).') -ForegroundColor Cyan
    }
    else {
        Write-Error (Get-LocalizedText 'Machine-wide Python packages still need administrator privileges. Run this script as administrator.')
        exit 1
    }
    foreach ($package in $missingPythonPackages) {
        Write-Host ''
        Write-Host (Get-LocalizedText -Text 'Installing Python package: {0}' -Arguments @($package)) -ForegroundColor Cyan
        $pipResult = Invoke-SetupProcess -FilePath $state.PythonPath -Arguments @('-m', 'pip', 'install', '--upgrade', $package) @localizationOptions
        if ($pipResult.StdOut) { Write-Host $pipResult.StdOut.TrimEnd() }
        if ($pipResult.StdErr) { Write-Host $pipResult.StdErr.TrimEnd() -ForegroundColor DarkYellow }
        if ($pipResult.ExitCode -ne 0) {
            Write-Error (Get-LocalizedText -Text 'pip failed to install {0} (exit code {1}).' -Arguments @($package, $pipResult.ExitCode))
            exit $pipResult.ExitCode
        }
    }

    $toolLocation = Get-PdfToolLocation -PreferredPythonPath $RuntimePythonPath
    $state = Get-PdfSetupState -ToolLocation $toolLocation @localizationOptions
    foreach ($line in Get-PdfSetupStateReport -State $state @localizationOptions) {
        if ($line.Color) { Write-Host $line.Text -ForegroundColor $line.Color } else { Write-Host $line.Text }
    }
    if (-not $state.OcrMyPdfAvailable -or -not $state.PikePdfAvailable) {
        Write-Error (Get-LocalizedText 'One or more dependencies are still missing after installation. Review the output above.')
        exit 1
    }
}

# --- Inspect, but do not download, Tesseract language data ----------------

if (-not $state.TrainingStatus -or -not $state.TrainingStatus.CheckSucceeded) {
    Write-Warning (Get-LocalizedText 'Tesseract is installed, but its language data could not be inspected.')
    exit 0
}

$requiredLanguages = @('deu', 'eng')
$recommendedLanguages = @('fra', 'ita', 'spa')
$missingRequiredLanguages = @($requiredLanguages | Where-Object { $state.TrainingStatus.Languages -notcontains $_ })
$missingRecommendedLanguages = @($recommendedLanguages | Where-Object { $state.TrainingStatus.Languages -notcontains $_ })
$missingLanguages = @($missingRequiredLanguages + $missingRecommendedLanguages)

if ($missingLanguages.Count -eq 0) {
    Write-Host ''
    Write-Host (Get-LocalizedText 'All default Tesseract language data is installed.') -ForegroundColor Green
    exit 0
}

Write-Host ''
if ($missingRequiredLanguages.Count -gt 0) {
    Write-Host (Get-LocalizedText -Text 'Missing required language data: {0}' -Arguments @(($missingRequiredLanguages -join ', '))) -ForegroundColor Yellow
}
if ($missingRecommendedLanguages.Count -gt 0) {
    Write-Host (Get-LocalizedText -Text 'Missing optional language data: {0}' -Arguments @(($missingRecommendedLanguages -join ', '))) -ForegroundColor DarkYellow
}
Write-Host (Get-LocalizedText -Text 'Please download these .traineddata files from {0}.' -Arguments @('https://github.com/tesseract-ocr/tessdata_best'))
Write-Host (Get-LocalizedText -Text 'Place the downloaded files in the Tesseract tessdata folder: {0}' -Arguments @($state.TrainingStatus.TessdataPath))
Write-Host (Get-LocalizedText 'This script does not download language data.')
