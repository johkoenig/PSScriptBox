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
    .\Setup-PdfProcessor.ps1
    Checks dependencies, installs missing software if needed, and reports
    missing Tesseract language data.

.EXAMPLE
    .\Setup-PdfProcessor.ps1 -EnglishOutput
    Runs the setup with English console output.

.NOTES
    Dependencies: Windows PowerShell 5.1 or later and Chocolatey. Chocolatey
    must be installed separately. System-wide installation requires
    administrator privileges. Python packages are installed in the selected
    interpreter. No OCR language data is downloaded by this script.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors

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

$script:OutputLanguage = if (
    $EnglishOutput -or [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'de'
) { 'en' } else { 'de' }
$script:GermanMessages = if ($script:OutputLanguage -eq 'de') {
    Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1')
}
else { @{} }

<#
.SYNOPSIS
    Returns a localized console message.

.DESCRIPTION
    Uses the German message catalog when German output is selected; otherwise
    returns the English source string. Formats the selected template when
    formatting arguments are provided.

.PARAMETER Text
    English source message and lookup key.

.PARAMETER Arguments
    Optional values used to format placeholders in the message.

.OUTPUTS
    System.String. The localized and optionally formatted message.
#>
function Get-LocalizedText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [AllowEmptyCollection()][object[]] $Arguments = @()
    )

    $template = if ($script:OutputLanguage -eq 'de' -and $script:GermanMessages.ContainsKey($Text)) {
        $script:GermanMessages[$Text]
    }
    else { $Text }
    if ($Arguments.Count -gt 0) { return $template -f $Arguments }
    return $template
}

<#
.SYNOPSIS
    Quotes an argument for Windows process invocation.

.DESCRIPTION
    Escapes quotation marks and trailing backslashes so PowerShell 5.1 can pass
    the value as a single process argument.

.PARAMETER Value
    Argument value to quote.

.OUTPUTS
    System.String. The quoted argument.
#>
function ConvertTo-QuotedArgument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Value)

    $escaped = [regex]::Replace($Value, '(\\)(?=")', '$1$1')
    if ($escaped.EndsWith('\')) { $escaped += '\' }
    $escaped = $escaped -replace '"', '\"'
    return '"' + $escaped + '"'
}

<#
.SYNOPSIS
    Runs an external program and captures its output.

.DESCRIPTION
    Starts the specified executable with redirected streams and reads both
    streams asynchronously to avoid pipe deadlocks.

.PARAMETER FilePath
    Executable path.

.PARAMETER Arguments
    Argument list for the executable.

.OUTPUTS
    PSCustomObject with ExitCode, StdOut, and StdErr.
#>
function Invoke-SetupProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = ($Arguments | ForEach-Object { ConvertTo-QuotedArgument -Value $_ }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw (Get-LocalizedText -Text 'Could not start process: {0}' -Arguments @($FilePath))
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdoutTask.GetAwaiter().GetResult()
            StdErr   = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

<#
.SYNOPSIS
    Finds an executable in the current PATH.

.DESCRIPTION
    Returns the path of the first matching command, or null when no command is
    available.

.PARAMETER Name
    Executable command name.

.OUTPUTS
    System.String or null.
#>
function Get-ExecutablePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) { return $null }
    return $command.Source
}

<#
.SYNOPSIS
    Gets Tesseract's installed language data.

.DESCRIPTION
    Reads `tesseract --list-langs` and returns available language codes and the
    local tessdata directory.

.PARAMETER TesseractPath
    Path to the Tesseract executable.

.OUTPUTS
    PSCustomObject with Languages, TessdataPath, and CheckSucceeded.
#>
function Get-TesseractTrainingStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $TesseractPath)

    $result = Invoke-SetupProcess -FilePath $TesseractPath -Arguments @('--list-langs')
    if ($result.ExitCode -ne 0) {
        return [pscustomobject]@{
            Languages      = @()
            TessdataPath   = $null
            CheckSucceeded = $false
        }
    }

    $tessdataPath = $null
    if ($result.StdOut -match 'List of available languages in "([^"]+)"') {
        $tessdataPath = $Matches[1]
    }
    if (-not $tessdataPath) {
        $tessdataPath = Join-Path -Path (Split-Path -Parent $TesseractPath) -ChildPath 'tessdata'
    }

    $languages = @(
        $result.StdOut -split '\r?\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^[A-Za-z0-9_]+$' -and $_ -ne 'List' }
    )
    return [pscustomobject]@{
        Languages      = $languages
        TessdataPath   = $tessdataPath
        CheckSucceeded = $true
    }
}

<#
.SYNOPSIS
    Collects the current PDF processor dependency state.

.DESCRIPTION
    Checks Chocolatey and Python executables, each Python package separately,
    Tesseract, Ghostscript, and installed Tesseract language data. This runs
    before any elevation.

.OUTPUTS
    PSCustomObject containing executable paths and dependency status.
#>
function Get-PdfSetupState {
    [CmdletBinding()]
    param()

    $chocolateyPath = Get-ExecutablePath -Name 'choco'
    $chocolateyAvailable = $false
    if ($chocolateyPath) {
        $chocolateyCheck = Invoke-SetupProcess -FilePath $chocolateyPath -Arguments @('--version')
        $chocolateyAvailable = $chocolateyCheck.ExitCode -eq 0
    }

    $pythonRuntime = Get-PdfPythonRuntime -PreferredPath $RuntimePythonPath
    $pythonPath = if ($pythonRuntime) { $pythonRuntime.Path } else { $null }
    $pythonAvailable = $false
    if ($pythonPath) {
        $pythonCheck = Invoke-SetupProcess -FilePath $pythonPath -Arguments @('--version')
        $pythonAvailable = $pythonCheck.ExitCode -eq 0
    }

    $ocrmypdfAvailable = $false
    $pikepdfAvailable = $false
    if ($pythonAvailable) {
        $ocrmypdfCheck = Invoke-SetupProcess -FilePath $pythonPath -Arguments @('-c', 'import ocrmypdf')
        $pikepdfCheck = Invoke-SetupProcess -FilePath $pythonPath -Arguments @('-c', 'import pikepdf')
        $ocrmypdfAvailable = $ocrmypdfCheck.ExitCode -eq 0
        $pikepdfAvailable = $pikepdfCheck.ExitCode -eq 0
    }

    $tesseractPath = Get-ExecutablePath -Name 'tesseract'
    $tesseractAvailable = $false
    if ($tesseractPath) {
        $tesseractCheck = Invoke-SetupProcess -FilePath $tesseractPath -Arguments @('--version')
        $tesseractAvailable = $tesseractCheck.ExitCode -eq 0
    }

    $ghostscriptPath = Get-ExecutablePath -Name 'gswin64c'
    if (-not $ghostscriptPath) { $ghostscriptPath = Get-ExecutablePath -Name 'gswin32c' }
    if (-not $ghostscriptPath) { $ghostscriptPath = Get-ExecutablePath -Name 'gs' }
    $ghostscriptAvailable = $false
    if ($ghostscriptPath) {
        $ghostscriptCheck = Invoke-SetupProcess -FilePath $ghostscriptPath -Arguments @('-version')
        $ghostscriptAvailable = $ghostscriptCheck.ExitCode -eq 0
    }

    $trainingStatus = $null
    if ($tesseractAvailable) {
        $trainingStatus = Get-TesseractTrainingStatus -TesseractPath $tesseractPath
    }

    return [pscustomobject]@{
        ChocolateyPath     = $chocolateyPath
        ChocolateyAvailable = $chocolateyAvailable
        PythonPath         = $pythonPath
        PythonAvailable    = $pythonAvailable
        PythonScope        = if ($pythonRuntime) { $pythonRuntime.Scope } else { $null }
        OcrMyPdfAvailable  = $ocrmypdfAvailable
        PikePdfAvailable   = $pikepdfAvailable
        TesseractPath      = $tesseractPath
        TesseractAvailable = $tesseractAvailable
        GhostscriptPath    = $ghostscriptPath
        GhostscriptAvailable = $ghostscriptAvailable
        TrainingStatus     = $trainingStatus
    }
}

<#
.SYNOPSIS
    Displays the dependency state.

.DESCRIPTION
    Reports whether each prerequisite is present and whether Tesseract language
    data could be inspected.

.PARAMETER State
    Dependency state returned by Get-PdfSetupState.

.OUTPUTS
    No pipeline output. Writes the state to the console.
#>
function Show-PdfSetupState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject] $State)

    Write-Host ''
    Write-Host (Get-LocalizedText 'Current dependency state:') -ForegroundColor Cyan
    Write-Host (Get-LocalizedText 'Chocolatey:') -ForegroundColor DarkCyan
    $chocolateyStatus = if ($State.ChocolateyAvailable) {
        Get-LocalizedText 'Present'
    }
    elseif ($State.ChocolateyPath) {
        Get-LocalizedText 'Found but failed its validation check'
    }
    else {
        Get-LocalizedText 'Missing'
    }
    Write-Host (Get-LocalizedText -Text '  {0}: {1}' -Arguments @('Chocolatey', $chocolateyStatus))

    Write-Host (Get-LocalizedText 'Python:') -ForegroundColor DarkCyan
    $pythonStatus = if ($State.PythonAvailable) {
        Get-LocalizedText 'Present'
    }
    elseif ($State.PythonPath) {
        Get-LocalizedText 'Found but failed its validation check'
    }
    else {
        Get-LocalizedText 'Missing'
    }
    Write-Host (Get-LocalizedText -Text '  {0}: {1}' -Arguments @('Python', $pythonStatus))
    if ($State.PythonPath) {
        Write-Host (Get-LocalizedText -Text '  Python executable: {0}' -Arguments @($State.PythonPath))
        $scopeLabel = if ($State.PythonScope -eq 'User') {
            Get-LocalizedText 'Current user'
        }
        else {
            Get-LocalizedText 'Machine-wide'
        }
        Write-Host (Get-LocalizedText -Text '  Python scope: {0}' -Arguments @($scopeLabel))
    }
    foreach ($module in @(
        @{ Name = 'OCRmyPDF'; Present = [bool]$State.OcrMyPdfAvailable }
        @{ Name = 'pikepdf'; Present = [bool]$State.PikePdfAvailable }
    )) {
        $status = if (-not $State.PythonAvailable) {
            Get-LocalizedText 'Not checked (Python is unavailable)'
        }
        elseif ($module.Present) {
            Get-LocalizedText 'Present'
        }
        else {
            Get-LocalizedText 'Missing'
        }
        Write-Host (Get-LocalizedText -Text '  Python package {0}: {1}' -Arguments @($module.Name, $status))
    }

    Write-Host (Get-LocalizedText 'Tesseract:') -ForegroundColor DarkCyan
    $tesseractStatus = if ($State.TesseractAvailable) {
        Get-LocalizedText 'Present'
    }
    elseif ($State.TesseractPath) {
        Get-LocalizedText 'Found but failed its validation check'
    }
    else {
        Get-LocalizedText 'Missing'
    }
    Write-Host (Get-LocalizedText -Text '  {0}: {1}' -Arguments @('Tesseract', $tesseractStatus))
    $ghostscriptStatus = if ($State.GhostscriptAvailable) {
        Get-LocalizedText 'Present'
    }
    elseif ($State.GhostscriptPath) {
        Get-LocalizedText 'Found but failed its validation check'
    }
    else {
        Get-LocalizedText 'Missing'
    }
    Write-Host (Get-LocalizedText -Text '  {0}: {1}' -Arguments @('Ghostscript', $ghostscriptStatus))
    if ($State.TrainingStatus) {
        $trainingResult = if ($State.TrainingStatus.CheckSucceeded) {
            Get-LocalizedText 'Inspected'
        }
        else {
            Get-LocalizedText 'Could not inspect'
        }
        Write-Host (Get-LocalizedText -Text '  Language data: {0}' -Arguments @($trainingResult))
    }
}

<#
.SYNOPSIS
    Restarts this script with administrator privileges.

.DESCRIPTION
    Starts a new elevated PowerShell process and waits for machine-wide
    Chocolatey package installation to finish.

.PARAMETER EnglishOutput
    Preserves the request for English output in the elevated process.

.PARAMETER RuntimePythonPath
    Preserves the selected interpreter path in the elevated process.

.OUTPUTS
    System.Int32. The elevated process exit code.
#>
function Start-ElevatedSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool] $EnglishOutput,
        [string] $RuntimePythonPath
    )

    $hostName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $hostPath = Get-ExecutablePath -Name $hostName
    if (-not $hostPath) { $hostPath = Join-Path $PSHOME $hostName }

    $childArguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $PSCommandPath
        '-ElevatedChild'
    )
    if ($EnglishOutput) { $childArguments += '-EnglishOutput' }
    if ($RuntimePythonPath) { $childArguments += @('-RuntimePythonPath', $RuntimePythonPath) }
    $argumentLine = ($childArguments | ForEach-Object { ConvertTo-QuotedArgument -Value $_ }) -join ' '
    $childProcess = Start-Process -FilePath $hostPath -Verb RunAs -ArgumentList $argumentLine -Wait -PassThru
    return $childProcess.ExitCode
}

<#
.SYNOPSIS
    Refreshes PATH values in the current process.

.DESCRIPTION
    Reloads machine and current-user PATH values after Chocolatey installs
    packages, allowing this setup process to find newly installed executables.

.OUTPUTS
    No pipeline output.
#>
function Update-ProcessPath {
    [CmdletBinding()]
    param()

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machinePath, $userPath) -join [System.IO.Path]::PathSeparator
}

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

$state = Get-PdfSetupState
Show-PdfSetupState -State $state

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
            $elevatedExitCode = Start-ElevatedSetup -EnglishOutput $EnglishOutput.IsPresent -RuntimePythonPath $state.PythonPath
            if ($elevatedExitCode -ne 0) {
                Write-Error (Get-LocalizedText -Text 'Elevated installation failed (exit code {0}).' -Arguments @($elevatedExitCode))
                exit $elevatedExitCode
            }
            Update-ProcessPath
            $state = Get-PdfSetupState
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
            $installResult = Invoke-SetupProcess -FilePath $state.ChocolateyPath -Arguments @('install', $package, '--yes')
            if ($installResult.StdOut) { Write-Host $installResult.StdOut.TrimEnd() }
            if ($installResult.StdErr) { Write-Host $installResult.StdErr.TrimEnd() -ForegroundColor DarkYellow }
            if ($installResult.ExitCode -ne 0) {
                Write-Error (Get-LocalizedText -Text 'Chocolatey failed to install {0} (exit code {1}).' -Arguments @($package, $installResult.ExitCode))
                exit $installResult.ExitCode
            }
        }

        Update-ProcessPath
        $state = Get-PdfSetupState
        if ($state.PythonScope -eq 'Machine') {
            $machinePythonPackages = @()
            if (-not $state.OcrMyPdfAvailable) { $machinePythonPackages += 'ocrmypdf' }
            if (-not $state.PikePdfAvailable) { $machinePythonPackages += 'pikepdf' }
            foreach ($package in $machinePythonPackages) {
                Write-Host ''
                Write-Host (Get-LocalizedText -Text 'Installing Python package in the machine-wide interpreter: {0}' -Arguments @($package)) -ForegroundColor Cyan
                $pipResult = Invoke-SetupProcess -FilePath $state.PythonPath -Arguments @('-m', 'pip', 'install', '--upgrade', $package)
                if ($pipResult.StdOut) { Write-Host $pipResult.StdOut.TrimEnd() }
                if ($pipResult.StdErr) { Write-Host $pipResult.StdErr.TrimEnd() -ForegroundColor DarkYellow }
                if ($pipResult.ExitCode -ne 0) {
                    Write-Error (Get-LocalizedText -Text 'pip failed to install {0} (exit code {1}).' -Arguments @($package, $pipResult.ExitCode))
                    exit $pipResult.ExitCode
                }
            }
            $state = Get-PdfSetupState
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
                $pipResult = Invoke-SetupProcess -FilePath $state.PythonPath -Arguments @('-m', 'pip', 'install', '--upgrade', $package)
                if ($pipResult.StdOut) { Write-Host $pipResult.StdOut.TrimEnd() }
                if ($pipResult.StdErr) { Write-Host $pipResult.StdErr.TrimEnd() -ForegroundColor DarkYellow }
                if ($pipResult.ExitCode -ne 0) {
                    Write-Error (Get-LocalizedText -Text 'pip failed to install {0} (exit code {1}).' -Arguments @($package, $pipResult.ExitCode))
                    exit $pipResult.ExitCode
                }
            }
            $state = Get-PdfSetupState
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
        $pipResult = Invoke-SetupProcess -FilePath $state.PythonPath -Arguments @('-m', 'pip', 'install', '--upgrade', $package)
        if ($pipResult.StdOut) { Write-Host $pipResult.StdOut.TrimEnd() }
        if ($pipResult.StdErr) { Write-Host $pipResult.StdErr.TrimEnd() -ForegroundColor DarkYellow }
        if ($pipResult.ExitCode -ne 0) {
            Write-Error (Get-LocalizedText -Text 'pip failed to install {0} (exit code {1}).' -Arguments @($package, $pipResult.ExitCode))
            exit $pipResult.ExitCode
        }
    }

    $state = Get-PdfSetupState
    Show-PdfSetupState -State $state
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
